"""ClinicDesk API.

Eight REST endpoints over a patients table, plus the health, readiness and
metrics endpoints Kubernetes and Prometheus need.
"""
import logging

from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import Patient
from app.schemas import PatientCreate, PatientOut, PatientUpdate

logging.basicConfig(level=settings.log_level)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="A small clinic front-desk queue, used as the capstone application.",
)

# The frontend is served from a different origin in development.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Exposes /metrics in Prometheus format: request counts, durations and
# in-progress gauges, labelled by handler, method and status.
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


# ----------------------------------------------------------------- health ----

@app.get("/health", tags=["health"])
def health():
    """Liveness. Deliberately does NOT touch the database.

    A liveness probe that checks dependencies will restart every pod when the
    database blips, turning a recoverable outage into a total one.
    """
    return {"status": "ok", "environment": settings.environment}


@app.get("/ready", tags=["health"])
def ready(db: Session = Depends(get_db)):
    """Readiness. This one DOES check the database, because a pod that cannot
    reach its database should be taken out of the Service."""
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001 - we want any failure to mean not-ready
        logger.warning("readiness check failed: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="database unreachable"
        ) from exc
    return {"status": "ready"}


# --------------------------------------------------------------- patients ----

@app.get("/api/patients", response_model=list[PatientOut], tags=["patients"])
def list_patients(
    db: Session = Depends(get_db),
    patient_status: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
):
    """List patients, optionally filtered by status. Paginated, because an
    unbounded list endpoint is a denial-of-service waiting to happen."""
    stmt = select(Patient).order_by(Patient.created_at.desc())
    if patient_status:
        stmt = stmt.where(Patient.status == patient_status)
    return db.scalars(stmt.limit(limit).offset(offset)).all()


@app.get("/api/patients/{patient_id}", response_model=PatientOut, tags=["patients"])
def get_patient(patient_id: int, db: Session = Depends(get_db)):
    patient = db.get(Patient, patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="patient not found")
    return patient


@app.post("/api/patients", response_model=PatientOut, status_code=201, tags=["patients"])
def create_patient(payload: PatientCreate, db: Session = Depends(get_db)):
    patient = Patient(**payload.model_dump())
    db.add(patient)
    db.commit()
    db.refresh(patient)
    logger.info("created patient id=%s", patient.id)
    return patient


@app.put("/api/patients/{patient_id}", response_model=PatientOut, tags=["patients"])
def update_patient(patient_id: int, payload: PatientUpdate, db: Session = Depends(get_db)):
    patient = db.get(Patient, patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="patient not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(patient, field, value)
    db.commit()
    db.refresh(patient)
    return patient


@app.delete("/api/patients/{patient_id}", status_code=204, tags=["patients"])
def delete_patient(patient_id: int, db: Session = Depends(get_db)):
    patient = db.get(Patient, patient_id)
    if patient is None:
        raise HTTPException(status_code=404, detail="patient not found")
    db.delete(patient)
    db.commit()
    return None


@app.get("/api/stats", tags=["patients"])
def stats(db: Session = Depends(get_db)):
    """Counts per status, for the frontend summary bar."""
    counts = {s: 0 for s in ("waiting", "in_consultation", "discharged")}
    for patient in db.scalars(select(Patient)).all():
        counts[patient.status] = counts.get(patient.status, 0) + 1
    return {"total": sum(counts.values()), "by_status": counts}
