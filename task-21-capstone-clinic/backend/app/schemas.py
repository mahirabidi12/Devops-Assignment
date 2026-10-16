"""Request and response shapes. Keeping these separate from the ORM models
means the API contract does not change just because a column does."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

Status = Literal["waiting", "in_consultation", "discharged"]


class PatientCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    age: int = Field(ge=0, le=130)
    phone: str = Field(min_length=1, max_length=20)
    notes: str | None = Field(default=None, max_length=5000)
    status: Status = "waiting"


class PatientUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=200)
    age: int | None = Field(default=None, ge=0, le=130)
    phone: str | None = Field(default=None, min_length=1, max_length=20)
    notes: str | None = Field(default=None, max_length=5000)
    status: Status | None = None


class PatientOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    age: int
    phone: str
    notes: str | None
    status: Status
    created_at: datetime
    updated_at: datetime
