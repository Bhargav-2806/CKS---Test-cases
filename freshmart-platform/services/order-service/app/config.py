from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str          = "postgresql://freshmart:freshmart@localhost:5432/freshmart"
    cart_service_url: str      = "http://localhost:8002"
    payment_service_url: str   = "http://localhost:8004"
    kafka_bootstrap_servers: str = "localhost:9092"
    kafka_enabled: bool        = False   # graceful — set True once Kafka is running
    port: int                  = 8003
    debug: bool                = False

    model_config = {"env_file": ".env"}


settings = Settings()
