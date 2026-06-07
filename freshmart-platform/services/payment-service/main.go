package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	kafkago "github.com/segmentio/kafka-go"
)

// ─── Config ───────────────────────────────────────────────────────────────────

type Config struct {
	DatabaseURL    string
	KafkaBootstrap string
	KafkaEnabled   bool
	Port           string

	// mTLS configuration — enabled when MTLS_ENABLED=true
	// Cert files are mounted from the payment-server-tls Secret (cert-manager)
	MTLSEnabled   bool
	MTLSCertFile  string // /certs/tls.crt  — server certificate
	MTLSKeyFile   string // /certs/tls.key  — server private key
	MTLSCAFile    string // /certs/ca.crt   — CA to verify client certificates
	MTLSClientCN  string // expected CommonName on client cert (must be "order-service")
}

func loadConfig() Config {
	kafkaEnabled := os.Getenv("KAFKA_ENABLED") == "true"
	mtlsEnabled  := os.Getenv("MTLS_ENABLED") == "true"
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}
	return Config{
		DatabaseURL:    getEnv("DATABASE_URL", "postgresql://freshmart:freshmart@localhost:5432/freshmart"),
		KafkaBootstrap: getEnv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
		KafkaEnabled:   kafkaEnabled,
		Port:           port,
		MTLSEnabled:    mtlsEnabled,
		MTLSCertFile:   getEnv("MTLS_CERT_FILE", "/certs/tls.crt"),
		MTLSKeyFile:    getEnv("MTLS_KEY_FILE",  "/certs/tls.key"),
		MTLSCAFile:     getEnv("MTLS_CA_FILE",   "/certs/ca.crt"),
		MTLSClientCN:   getEnv("MTLS_CLIENT_CN", "order-service"),
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// ─── Models ───────────────────────────────────────────────────────────────────

type ProcessPaymentRequest struct {
	OrderID      string  `json:"order_id"`
	Amount       float64 `json:"amount"`
	CardLastFour string  `json:"card_last_four"`
}

type PaymentResponse struct {
	ID           string  `json:"id"`
	OrderID      string  `json:"order_id"`
	Amount       float64 `json:"amount"`
	Status       string  `json:"status"`
	CardLastFour string  `json:"card_last_four"`
	CreatedAt    string  `json:"created_at"`
}

// ─── Server ───────────────────────────────────────────────────────────────────

type Server struct {
	cfg    Config
	db     *pgxpool.Pool
	kafka  *kafkago.Writer
}

func NewServer(cfg Config) (*Server, error) {
	// DB connection with retries — track both New() and Ping() failures
	var pool *pgxpool.Pool
	var err error
	for i := 0; i < 10; i++ {
		pool, err = pgxpool.New(context.Background(), cfg.DatabaseURL)
		if err == nil {
			if pingErr := pool.Ping(context.Background()); pingErr == nil {
				break // connected successfully
			} else {
				pool.Close()
				err = pingErr // treat Ping failure as the loop error
			}
		}
		log.Printf("DB not ready, retrying in 3s (%d/10)...", i+1)
		time.Sleep(3 * time.Second)
	}
	if err != nil {
		return nil, fmt.Errorf("failed to connect to DB after retries: %w", err)
	}

	// Create payments table
	_, err = pool.Exec(context.Background(), `
		CREATE TABLE IF NOT EXISTS payments (
			id             VARCHAR(50)    PRIMARY KEY,
			order_id       VARCHAR(50)    NOT NULL,
			amount         NUMERIC(10,2)  NOT NULL,
			status         VARCHAR(50)    NOT NULL DEFAULT 'pending',
			card_last_four VARCHAR(4),
			created_at     TIMESTAMPTZ    DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);
	`)
	if err != nil {
		return nil, fmt.Errorf("failed to create payments table: %w", err)
	}

	// Kafka writer (optional)
	var writer *kafkago.Writer
	if cfg.KafkaEnabled {
		writer = &kafkago.Writer{
			Addr:         kafkago.TCP(cfg.KafkaBootstrap),
			Topic:        "payment.result",
			Balancer:     &kafkago.LeastBytes{},
			WriteTimeout: 5 * time.Second,
		}
		log.Printf("Kafka writer configured for %s", cfg.KafkaBootstrap)
	}

	return &Server{cfg: cfg, db: pool, kafka: writer}, nil
}

// ─── Handlers ─────────────────────────────────────────────────────────────────

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	respondJSON(w, http.StatusOK, map[string]string{
		"status":  "healthy",
		"service": "payment-service",
	})
}

func (s *Server) handleProcessPayment(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req ProcessPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.OrderID == "" || req.Amount <= 0 {
		respondError(w, http.StatusBadRequest, "order_id and amount are required")
		return
	}

	paymentID := "PAY-" + uuid.New().String()[:8]

	// Mock payment processing — always succeeds in demo
	// In real world: call Stripe/Adyen/etc API here
	status := "success"

	// Persist payment record
	_, err := s.db.Exec(context.Background(),
		`INSERT INTO payments (id, order_id, amount, status, card_last_four)
		 VALUES ($1, $2, $3, $4, $5)`,
		paymentID, req.OrderID, req.Amount, status, req.CardLastFour,
	)
	if err != nil {
		log.Printf("ERROR inserting payment: %v", err)
		respondError(w, http.StatusInternalServerError, "payment storage failed")
		return
	}

	log.Printf("Payment processed: id=%s order=%s amount=%.2f status=%s",
		paymentID, req.OrderID, req.Amount, status)

	// Publish to Kafka (best-effort)
	if s.kafka != nil {
		event, _ := json.Marshal(map[string]any{
			"payment_id": paymentID,
			"order_id":   req.OrderID,
			"amount":     req.Amount,
			"status":     status,
		})
		if err := s.kafka.WriteMessages(context.Background(),
			kafkago.Message{Value: event},
		); err != nil {
			log.Printf("WARN Kafka publish failed: %v", err)
		}
	}

	respondJSON(w, http.StatusCreated, PaymentResponse{
		ID:           paymentID,
		OrderID:      req.OrderID,
		Amount:       req.Amount,
		Status:       status,
		CardLastFour: req.CardLastFour,
		CreatedAt:    time.Now().UTC().Format(time.RFC3339),
	})
}

func (s *Server) handleGetPayment(w http.ResponseWriter, r *http.Request) {
	paymentID := r.PathValue("id") // Go 1.22+ built-in path params
	if paymentID == "" {
		respondError(w, http.StatusBadRequest, "payment id required")
		return
	}

	var p PaymentResponse
	var createdAt time.Time // scan TIMESTAMPTZ into time.Time, then format as string

	err := s.db.QueryRow(context.Background(),
		`SELECT id, order_id, amount, status, COALESCE(card_last_four,''), created_at
		 FROM payments WHERE id = $1`, paymentID,
	).Scan(&p.ID, &p.OrderID, &p.Amount, &p.Status, &p.CardLastFour, &createdAt)

	if err != nil {
		respondError(w, http.StatusNotFound, "payment not found")
		return
	}
	p.CreatedAt = createdAt.UTC().Format(time.RFC3339)
	respondJSON(w, http.StatusOK, p)
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

func respondJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func respondError(w http.ResponseWriter, code int, msg string) {
	respondJSON(w, code, map[string]string{"error": msg})
}

// ─── mTLS Server ──────────────────────────────────────────────────────────────

// buildMTLSConfig creates a tls.Config that:
//   1. Presents the server's certificate to clients
//   2. Requires clients to present a certificate (mutual TLS)
//   3. Verifies the client cert is signed by our CA
//   4. Verifies the client cert's CN is exactly "order-service"
//      → only order-service can call payment-service, enforced at TLS layer
func (s *Server) buildMTLSConfig() (*tls.Config, error) {
	// Load server cert + key
	serverCert, err := tls.LoadX509KeyPair(s.cfg.MTLSCertFile, s.cfg.MTLSKeyFile)
	if err != nil {
		return nil, fmt.Errorf("loading server cert: %w", err)
	}

	// Load CA cert for verifying client certificates
	caPEM, err := os.ReadFile(s.cfg.MTLSCAFile)
	if err != nil {
		return nil, fmt.Errorf("reading CA cert: %w", err)
	}
	caPool := x509.NewCertPool()
	if !caPool.AppendCertsFromPEM(caPEM) {
		return nil, fmt.Errorf("failed to parse CA cert PEM")
	}

	expectedCN := s.cfg.MTLSClientCN

	return &tls.Config{
		Certificates: []tls.Certificate{serverCert},

		// RequireAndVerifyClientCert: client MUST present a cert signed by caPool.
		// Connections without a valid client cert are rejected at TLS handshake.
		ClientAuth: tls.RequireAndVerifyClientCert,
		ClientCAs:  caPool,

		// Minimum TLS 1.2 — disables TLS 1.0 and 1.1
		MinVersion: tls.VersionTLS12,

		// Strong cipher suites only (ECDHE + AES-GCM or CHACHA20)
		CipherSuites: []uint16{
			tls.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
			tls.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,
			tls.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,
		},

		// Additional identity check: verify client CN == "order-service"
		// This runs AFTER cert chain validation succeeds.
		// Prevents any other service (with a valid cert from our CA) from calling
		// payment-service — only order-service is authorized.
		VerifyPeerCertificate: func(_ [][]byte, verifiedChains [][]*x509.Certificate) error {
			if len(verifiedChains) == 0 || len(verifiedChains[0]) == 0 {
				return fmt.Errorf("mTLS: no verified certificate chain")
			}
			clientCN := verifiedChains[0][0].Subject.CommonName
			if clientCN != expectedCN {
				log.Printf("mTLS REJECTED: client CN=%q (expected %q)", clientCN, expectedCN)
				return fmt.Errorf("unauthorized client: CN=%q is not permitted to call payment-service", clientCN)
			}
			log.Printf("mTLS OK: client authenticated — CN=%s", clientCN)
			return nil
		},
	}, nil
}

// ─── Main ─────────────────────────────────────────────────────────────────────

func main() {
	cfg := loadConfig()

	srv, err := NewServer(cfg)
	if err != nil {
		log.Fatalf("Server init failed: %v", err)
	}
	defer srv.db.Close()
	if srv.kafka != nil {
		defer srv.kafka.Close()
	}

	mux := http.NewServeMux()
	// Go 1.22+ method routing: exactly ONE space between method and path
	mux.HandleFunc("GET /health",            srv.handleHealth)
	mux.HandleFunc("POST /api/payments",     srv.handleProcessPayment)
	mux.HandleFunc("GET /api/payments/{id}", srv.handleGetPayment)

	httpServer := &http.Server{
		Addr:    ":" + cfg.Port,
		Handler: mux,
	}

	if cfg.MTLSEnabled {
		// ── mTLS mode: mutual TLS — both sides authenticate ──────────────────
		tlsCfg, err := srv.buildMTLSConfig()
		if err != nil {
			log.Fatalf("mTLS config failed: %v", err)
		}
		httpServer.TLSConfig = tlsCfg

		log.Printf("Payment service listening with mTLS on :%s (client CN required: %s)",
			cfg.Port, cfg.MTLSClientCN)

		// ListenAndServeTLS("", "") — cert/key already loaded in TLSConfig
		if err := httpServer.ListenAndServeTLS("", ""); err != nil {
			log.Fatalf("mTLS server failed: %v", err)
		}
	} else {
		// ── Plain HTTP mode (Phase 3 default — no certs mounted) ─────────────
		log.Printf("Payment service listening on :%s (plain HTTP — set MTLS_ENABLED=true for mTLS)",
			cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil {
			log.Fatalf("Server failed: %v", err)
		}
	}
}
