import os
from datetime import date, datetime, timedelta, timezone
from typing import Literal

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from supabase import Client, create_client

load_dotenv()

supabase: Client = create_client(
    os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"]
)

app = FastAPI(title="Pomodoro API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


class SessionIn(BaseModel):
    type: Literal["focus", "break"]
    duration_seconds: int = Field(gt=0)
    round: int = Field(gt=0)


class SettingsIn(BaseModel):
    work_minutes: int = Field(gt=0, le=180)
    break_minutes: int = Field(gt=0, le=60)
    rounds: int = Field(gt=0, le=20)


@app.post("/api/sessions", status_code=201)
def create_session(session: SessionIn):
    completed_at = datetime.now(timezone.utc).isoformat()
    result = (
        supabase.table("sessions")
        .insert(
            {
                "type": session.type,
                "duration_seconds": session.duration_seconds,
                "round": session.round,
                "completed_at": completed_at,
            }
        )
        .execute()
    )
    return result.data[0]


@app.get("/api/sessions")
def list_sessions(limit: int = 50):
    result = (
        supabase.table("sessions")
        .select("id, type, duration_seconds, round, completed_at")
        .order("id", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data


@app.get("/api/stats")
def get_stats():
    result = (
        supabase.table("sessions")
        .select("duration_seconds, completed_at")
        .eq("type", "focus")
        .execute()
    )
    rows = result.data

    today = date.today().isoformat()
    today_seconds = sum(r["duration_seconds"] for r in rows if r["completed_at"][:10] == today)
    today_sessions = sum(1 for r in rows if r["completed_at"][:10] == today)
    total_seconds = sum(r["duration_seconds"] for r in rows)

    focus_dates = {r["completed_at"][:10] for r in rows}
    streak = 0
    cursor_date = date.today()
    while cursor_date.isoformat() in focus_dates:
        streak += 1
        cursor_date -= timedelta(days=1)

    return {
        "today_focus_minutes": round(today_seconds / 60, 1),
        "today_sessions": today_sessions,
        "total_focus_minutes": round(total_seconds / 60, 1),
        "current_streak_days": streak,
    }


@app.get("/api/settings")
def get_settings():
    result = (
        supabase.table("settings")
        .select("work_minutes, break_minutes, rounds")
        .eq("id", 1)
        .single()
        .execute()
    )
    return result.data


@app.put("/api/settings")
def update_settings(settings: SettingsIn):
    supabase.table("settings").update(
        {
            "work_minutes": settings.work_minutes,
            "break_minutes": settings.break_minutes,
            "rounds": settings.rounds,
        }
    ).eq("id", 1).execute()
    return settings
