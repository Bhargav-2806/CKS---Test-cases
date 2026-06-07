from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://freshmart:freshmart@localhost:5432/freshmart"
    product_service_url: str = "http://localhost:8001"
    port: int = 8002
    debug: bool = False

    model_config = {"env_file": ".env"}


settings = Settings()
