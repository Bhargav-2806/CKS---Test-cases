package main

import (
	"context"
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
	DatabaseURL      string
	KafkaBootstrap   string
	KafkaEnabled     bool
	Port             string
}

func loadConfig() Config {
	kafkaEnabled := os.Getenv("KAFKA_ENABLED") == "true"
	port := os.Getenv("PORT")
	if port == "" {
		port = "8004"
	}
	return Config{
		DatabaseURL:    getEnv("DATABASE_URL", "postgresql://freshmart:freshmart@localhost:5432/freshmart"),
		KafkaBootstrap: getEnv("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
		KafkaEnabled:   kafkaEnabled,
		Port:           port,
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

	log.Printf("Payment service listening on :%s", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, mux); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}
