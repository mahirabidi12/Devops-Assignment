"""Configuration, read from the environment. Nothing secret is ever defaulted
to a real value - the defaults here are only enough to run locally."""
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg2://clinic:clinic@localhost:5432/clinic"
    app_name: str = "ClinicDesk API"
    environment: str = "development"
    log_level: str = "INFO"

    class Config:
        env_file = ".env"
        env_prefix = ""


settings = Settings()
