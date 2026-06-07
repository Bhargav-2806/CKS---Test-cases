from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql://freshmart:freshmart@localhost:5432/freshmart"
    port: int = 8001
    debug: bool = False

    model_config = {"env_file": ".env"}


settings = Settings()
