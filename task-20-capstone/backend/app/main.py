"""TaskBoard API.

Six REST endpoints over a tasks table, plus the health, readiness and metrics
endpoints Kubernetes and Prometheus need.
"""
import logging

from fastapi import Depends, FastAPI, HTTPException, Query, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import select, text
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.models import Task
from app.schemas import TaskCreate, TaskOut, TaskUpdate

logging.basicConfig(level=settings.log_level)
logger = logging.getLogger(__name__)

app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    description="A small task board, used as the capstone application.",
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


# ------------------------------------------------------------------ tasks ----

@app.get("/api/tasks", response_model=list[TaskOut], tags=["tasks"])
def list_tasks(
    db: Session = Depends(get_db),
    task_status: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
):
    """List tasks, optionally filtered by status. Paginated, because an
    unbounded list endpoint is a denial-of-service waiting to happen."""
    stmt = select(Task).order_by(Task.created_at.desc())
    if task_status:
        stmt = stmt.where(Task.status == task_status)
    return db.scalars(stmt.limit(limit).offset(offset)).all()


@app.get("/api/tasks/{task_id}", response_model=TaskOut, tags=["tasks"])
def get_task(task_id: int, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    return task


@app.post("/api/tasks", response_model=TaskOut, status_code=201, tags=["tasks"])
def create_task(payload: TaskCreate, db: Session = Depends(get_db)):
    task = Task(**payload.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    logger.info("created task id=%s", task.id)
    return task


@app.put("/api/tasks/{task_id}", response_model=TaskOut, tags=["tasks"])
def update_task(task_id: int, payload: TaskUpdate, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(task, field, value)
    db.commit()
    db.refresh(task)
    return task


@app.delete("/api/tasks/{task_id}", status_code=204, tags=["tasks"])
def delete_task(task_id: int, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="task not found")
    db.delete(task)
    db.commit()
    return None


@app.get("/api/stats", tags=["tasks"])
def stats(db: Session = Depends(get_db)):
    """Counts per status, for the frontend summary bar."""
    counts = {s: 0 for s in ("todo", "in_progress", "done")}
    for task in db.scalars(select(Task)).all():
        counts[task.status] = counts.get(task.status, 0) + 1
    return {"total": sum(counts.values()), "by_status": counts}
