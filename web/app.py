from flask import Flask, render_template, redirect, url_for, abort
from sqlalchemy import create_engine, text
import os

DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///../db/sqlite/golfstats.db')

# SQLAlchemy engine; sqlite needs special connect_args
if DATABASE_URL.startswith('sqlite'):
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
else:
    engine = create_engine(DATABASE_URL)

app = Flask(__name__)


@app.route('/')
def index():
    return redirect(url_for('players'))


@app.route('/players')
def players():
    with engine.connect() as conn:
        rows = conn.execute(text("SELECT * FROM vw_Player_Summary ORDER BY avg_score ASC")).mappings().all()
    return render_template('players.html', players=rows)


@app.route('/player/<int:member_id>')
def player(member_id):
    with engine.connect() as conn:
        summary = conn.execute(
            text("SELECT * FROM vw_Player_Summary WHERE member_id = :id"), {"id": member_id}
        ).mappings().first()
        if not summary:
            abort(404)

        holes = conn.execute(
            text("SELECT * FROM vw_Player_HoleAverages WHERE member_id = :id ORDER BY hole_number"), {"id": member_id}
        ).mappings().all()

        rounds = conn.execute(
            text("SELECT * FROM vw_Player_RecentRounds WHERE member_id = :id ORDER BY date_played DESC"), {"id": member_id}
        ).mappings().all()

        perf = conn.execute(
            text("SELECT * FROM vw_Player_PerformanceByCourse WHERE member_id = :id ORDER BY avg_score ASC"), {"id": member_id}
        ).mappings().all()

        handicap = conn.execute(
            text("SELECT * FROM vw_Player_HandicapEstimate WHERE member_id = :id"), {"id": member_id}
        ).mappings().first()

    return render_template('player.html', summary=summary, holes=holes, rounds=rounds, perf=perf, handicap=handicap)


if __name__ == '__main__':
    # For local development only
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 5000)), debug=True)
