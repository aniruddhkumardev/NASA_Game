import React, { useEffect, useMemo, useReducer } from "react";

/* ------------------------------------------------------------------ *
 * LunarOperationsHUD
 * Self-contained mission telemetry + surface-operations overlay.
 * No UI library required: all styling ships inside this file.
 * ------------------------------------------------------------------ */

const TOTAL_DAYS = 180;
const TICK_MS = 250;
const DAY_SECONDS = 75; // simulated seconds per lunar day at 1x
const LOG_LIMIT = 24;

const PHASES = [
  { id: "cruise", label: "Launch & Cruise" },
  { id: "orbit", label: "Lunar Orbit" },
  { id: "descent", label: "Powered Descent" },
  { id: "surface", label: "Surface Ops" },
  { id: "cryo", label: "Cryo Analysis" },
  { id: "return", label: "Sample Return" },
];

const OPERATIONS = [
  {
    id: "ice",
    code: "SO-01",
    label: "Water-Ice Traverse Survey",
    detail: "Rover · sector C-7 · 4.2 km traverse",
    start: 62,
    duration: 95,
    tone: "cyan",
  },
  {
    id: "regolith",
    code: "SO-02",
    label: "Regolith Sampling",
    detail: "Auger drill · 1.8 m core · sample bay 2",
    start: 34,
    duration: 150,
    tone: "amber",
  },
  {
    id: "psr",
    code: "SO-03",
    label: "Shadowed Crater Survey",
    detail: "Laser spectrometer · PSR-9 · 41 K",
    start: 88,
    duration: 240,
    tone: "violet",
  },
  {
    id: "power",
    code: "SO-04",
    label: "Solar Array Recharge",
    detail: "Array B · sun angle 31.4° · 412 W",
    start: 51,
    duration: 110,
    tone: "green",
  },
];

const SEED_LOG = [
  { text: "PSR crater survey pass 3 initiated", tone: "info" },
  { text: "Pragyan-2 rover deployed · odometry nominal", tone: "success" },
  { text: "Vikram lander touchdown confirmed · tilt 0.4°", tone: "success" },
];

/* ----------------------------- helpers ---------------------------- */

const clamp = (value, min = 0, max = 100) =>
  Math.min(max, Math.max(min, value));

const pad = (value, size = 2) =>
  String(Math.floor(Math.abs(value))).padStart(size, "0");

const signalAt = (t) =>
  88 + Math.sin(t * 0.09) * 7 + Math.cos(t * 0.31) * 2;

const formatEta = (seconds) => {
  const total = Math.max(0, Math.ceil(seconds));
  return `${pad(total / 60)}:${pad(total % 60)}`;
};

const formatClock = (day, dayProgress, elapsed) => {
  const minutesIntoDay = dayProgress * 24 * 60;
  return `T+${pad(day, 3)}D ${pad(minutesIntoDay / 60)}:${pad(
    minutesIntoDay % 60,
  )}:${pad(elapsed % 60)}`;
};

const buildInitialState = (initialDay, initialPhase) => {
  const ops = OPERATIONS.map((op) => ({
    ...op,
    progress: op.start,
  }));

  return {
    running: true,
    speed: 1,
    day: clamp(initialDay, 1, TOTAL_DAYS),
    dayProgress: 0.28,
    phaseIndex: clamp(initialPhase, 0, PHASES.length - 1),
    elapsed: 0,
    seq: SEED_LOG.length,
    ops,
    log: SEED_LOG.map((entry, index) => ({
      id: SEED_LOG.length - index,
      clock: formatClock(initialDay, 0.28, 0),
      text: entry.text,
      tone: entry.tone,
    })),
    history: Array.from({ length: 28 }, (_, index) => signalAt(index * 1.7)),
    missionComplete: false,
  };
};

/* ----------------------------- reducer ---------------------------- */

function reducer(state, action) {
  switch (action.type) {
    case "tick": {
      if (!state.running || state.missionComplete) return state;

      const dt = (TICK_MS / 1000) * state.speed;
      const elapsed = state.elapsed + dt;
      let day = state.day;
      let dayProgress = state.dayProgress + dt / DAY_SECONDS;
      let phaseIndex = state.phaseIndex;
      let seq = state.seq;
      let log = state.log;

      const logEvent = (text, tone) => {
        seq += 1;
        log = [
          {
            id: seq,
            clock: formatClock(day, dayProgress, elapsed),
            text,
            tone,
          },
          ...log,
        ].slice(0, LOG_LIMIT);
      };

      if (dayProgress >= 1) {
        if (day >= TOTAL_DAYS) {
          dayProgress = 1;
        } else {
          dayProgress -= 1;
          day += 1;
          logEvent(`Lunar day ${day} begins · terminator crossing nominal`, "info");
        }
      }

      const ops = state.ops.map((op) => {
        if (op.progress >= 100) return op;
        const progress = clamp(op.progress + (dt / op.duration) * 100);
        if (progress >= 100) {
          logEvent(`${op.code} ${op.label} — complete`, "success");
        }
        return { ...op, progress };
      });

      if (phaseIndex === 3 && ops.every((op) => op.progress >= 100)) {
        phaseIndex = 4;
        logEvent("Surface operations archived · cryo analysis initiated", "success");
      }

      const missionComplete = day >= TOTAL_DAYS && dayProgress >= 1;
      if (missionComplete && !state.missionComplete) {
        logEvent("Lunar day 180 complete · mission profile satisfied", "success");
      }

      const history = [
        ...state.history.slice(-39),
        signalAt(elapsed),
      ];

      return {
        ...state,
        running: missionComplete ? false : state.running,
        elapsed,
        day,
        dayProgress,
        phaseIndex,
        ops,
        seq,
        log,
        history,
        missionComplete,
      };
    }

    case "toggle":
      return { ...state, running: !state.running };

    case "speed":
      return { ...state, speed: action.speed };

    case "reset":
      return buildInitialState(action.day, action.phase);

    default:
      return state;
  }
}

/* ---------------------------- sub-views --------------------------- */

function StatusBadge({ tone = "ok", icon, label, detail }) {
  return (
    <div className="loh-badge" data-tone={tone}>
      <span className="loh-badge-icon" aria-hidden="true">
        {icon}
      </span>
      <span className="loh-badge-copy">
        <span className="loh-badge-label">{label}</span>
        <span className="loh-badge-detail">{detail}</span>
      </span>
    </div>
  );
}

function OperationRow({ op, speed }) {
  const done = op.progress >= 100;
  const remaining = ((100 - op.progress) / 100) * op.duration;
  const eta = Math.ceil(remaining / speed);

  return (
    <article className={`loh-op ${done ? "is-done" : ""}`} data-tone={op.tone}>
      <div className="loh-op-head">
        <span className="loh-op-code">{op.code}</span>
        <h3 className="loh-op-label">{op.label}</h3>
        <span className="loh-op-pct">
          {Math.round(op.progress)}
          <small>%</small>
        </span>
      </div>

      <div
        className="loh-bar"
        role="progressbar"
        aria-label={op.label}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={Math.round(op.progress)}
        aria-valuetext={`${Math.round(op.progress)} percent`}
      >
        <span className="loh-bar-fill" style={{ width: `${op.progress}%` }} />
        <span className="loh-bar-ticks" aria-hidden="true" />
      </div>

      <div className="loh-op-meta">
        <span className="loh-op-detail">{op.detail}</span>
        <span className={done ? "loh-op-tag is-complete" : "loh-op-tag"}>
          {done ? "COMPLETE" : `ETA ${formatEta(eta)}`}
        </span>
      </div>
    </article>
  );
}

function Sparkline({ data }) {
  const max = data.length - 1 || 1;
  const points = data
    .map((value, index) => {
      const x = (index / max) * 100;
      const y = 32 - clamp(value, 0, 100) * 0.3;
      return `${x.toFixed(2)},${y.toFixed(2)}`;
    })
    .join(" ");

  return (
    <svg
      className="loh-spark"
      viewBox="0 0 100 32"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <defs>
        <linearGradient id="loh-spark-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="rgba(242, 242, 242, 0.35)" />
          <stop offset="100%" stopColor="rgba(242, 242, 242, 0)" />
        </linearGradient>
      </defs>
      <polyline className="loh-spark-area" points={`0,32 ${points} 100,32`} />
      <polyline className="loh-spark-line" points={points} />
    </svg>
  );
}

function IconSignal() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
      <path d="M4 15a8 8 0 0 1 8-8" strokeLinecap="round" />
      <path d="M4 19a12 12 0 0 1 12-12" strokeLinecap="round" />
      <circle cx="5" cy="19" r="1.4" fill="currentColor" stroke="none" />
    </svg>
  );
}

function IconShield() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
      <path d="M12 3 5 6v6c0 4 3 7 7 9 4-2 7-5 7-9V6l-7-3Z" strokeLinejoin="round" />
      <path d="m9 12 2.2 2.2L15.5 10" strokeLinecap="round" />
    </svg>
  );
}

function IconThermal() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
      <path d="M12 4a2.2 2.2 0 0 0-2.2 2.2v7.1a4 4 0 1 0 4.4 0V6.2A2.2 2.2 0 0 0 12 4Z" strokeLinejoin="round" />
      <path d="M12 9v6" strokeLinecap="round" />
    </svg>
  );
}

function IconDrill() {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7">
      <path d="M8 4h8l-1 5H9L8 4Z" strokeLinejoin="round" />
      <path d="M11 9v8" strokeLinecap="round" />
      <path d="m11 17-2 3m2-3 2 3" strokeLinecap="round" />
      <path d="M9 12h4" strokeLinecap="round" />
    </svg>
  );
}

/* ------------------------------ main ------------------------------ */

export default function LunarOperationsHUD({
  initialDay = 47,
  initialPhase = 3,
  className = "",
}) {
  const [state, dispatch] = useReducer(
    reducer,
    undefined,
    () => buildInitialState(initialDay, initialPhase),
  );

  const {
    running,
    speed,
    day,
    dayProgress,
    phaseIndex,
    elapsed,
    ops,
    log,
    history,
    missionComplete,
  } = state;

  useEffect(() => {
    if (!running || missionComplete) return undefined;
    const timer = setInterval(() => dispatch({ type: "tick" }), TICK_MS);
    return () => clearInterval(timer);
  }, [running, missionComplete]);

  useEffect(() => {
    const onKeyDown = (event) => {
      const target = event.target;
      if (
        target instanceof Element &&
        target.closest("button, a, input, select, textarea")
      ) {
        return;
      }
      if (event.code === "Space") {
        event.preventDefault();
        dispatch({ type: "toggle" });
      } else if (event.key === "r" || event.key === "R") {
        dispatch({ type: "reset", day: initialDay, phase: initialPhase });
      } else if (["1", "2", "4"].includes(event.key)) {
        dispatch({ type: "speed", speed: Number(event.key) });
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [initialDay, initialPhase]);

  const telemetry = useMemo(() => {
    const t = elapsed;
    return {
      power: 412 + Math.sin(t * 0.11) * 16 + Math.sin(t * 0.47) * 5,
      signal: signalAt(t),
      temp: -172.6 + Math.sin(t * 0.05) * 4.2,
      battery: clamp(92 - dayProgress * 6, 18, 100),
      latency: 1.24 + Math.sin(t * 0.07) * 0.06,
      odometer: 3.82 + (ops[0].progress / 100) * 0.42,
      radiation: 0.42 + Math.sin(t * 0.03) * 0.04,
    };
  }, [elapsed, dayProgress, ops]);

  const activeOps = ops.filter((op) => op.progress < 100).length;
  const missionRatio = clamp(
    ((day - 1 + dayProgress) / TOTAL_DAYS) * 100,
  );
  const dayClock = formatClock(day, dayProgress, elapsed);

  return (
    <div
      className={`loh ${className}`.trim()}
      role="region"
      aria-label="Lunar surface operations HUD"
    >
      <style>{HUD_CSS}</style>

      <div className="loh-shell">
        <div className="loh-scanlines" aria-hidden="true" />
        <div className="loh-glow" aria-hidden="true" />

        {/* -------------------------- header ------------------------- */}
        <header className="loh-header">
          <div className="loh-ident">
            <span className="loh-kicker">
              <i className="loh-pulse" aria-hidden="true" />
              ISRO · LUNAR MISSION CONTROL
            </span>
            <h1 className="loh-title">
              CHANDRAYAAN-4<span>Surface Operations</span>
            </h1>
            <p className="loh-sub">
              Vikram lander · Pragyan-2 rover · Shackleton sector
            </p>
          </div>

          <div className="loh-dayblock">
            <span className="loh-label">Mission Clock</span>
            <p className="loh-dayvalue">
              LUNAR DAY <strong>{pad(day, 3)}</strong>
              <em>/ {TOTAL_DAYS}</em>
            </p>
            <div
              className="loh-rail"
              role="progressbar"
              aria-label="Mission timeline"
              aria-valuemin={0}
              aria-valuemax={TOTAL_DAYS}
              aria-valuenow={day}
            >
              {Array.from({ length: 24 }, (_, index) => (
                <span
                  key={index}
                  className={
                    (index + 0.5) / 24 <= missionRatio / 100 ? "is-on" : ""
                  }
                />
              ))}
            </div>
            <div className="loh-clockrow">
              <span className="loh-clock">{dayClock}</span>
              <span className={`loh-link ${running ? "is-live" : ""}`}>
                {missionComplete
                  ? "MISSION COMPLETE"
                  : running
                    ? "Telemetry Live"
                    : "Sim Paused"}
              </span>
            </div>
          </div>
        </header>

        {/* -------------------------- phases ------------------------- */}
        <div className="loh-phases" role="list" aria-label="Mission phases">
          {PHASES.map((phase, index) => {
            const status =
              index < phaseIndex
                ? "is-done"
                : index === phaseIndex
                  ? "is-active"
                  : "is-pending";
            return (
              <div
                key={phase.id}
                className={`loh-phase ${status}`}
                role="listitem"
                aria-current={index === phaseIndex ? "step" : undefined}
              >
                <span className="loh-phase-dot" aria-hidden="true" />
                <span className="loh-phase-label">{phase.label}</span>
              </div>
            );
          })}
        </div>

        {/* --------------------------- body -------------------------- */}
        <div className="loh-grid">
          <section className="loh-panel loh-ops" aria-labelledby="loh-ops-title">
            <div className="loh-panel-head">
              <div>
                <span className="loh-label">Surface Operations</span>
                <h2 id="loh-ops-title">Active Survey Queue</h2>
              </div>
              <span className="loh-count">
                {activeOps > 0 ? `${activeOps} ACTIVE` : "ALL COMPLETE"}
              </span>
            </div>

            <div className="loh-oplist">
              {ops.map((op) => (
                <OperationRow key={op.id} op={op} speed={speed} />
              ))}
            </div>

            <div className="loh-ops-foot">
              <span>
                SITE <b>SHACKLETON · C-7</b>
              </span>
              <span>
                SUN ELEV <b>31.4°</b>
              </span>
              <span>
                REGOLITH <b>-168 °C</b>
              </span>
              <span>
                ODO <b>{telemetry.odometer.toFixed(2)} km</b>
              </span>
            </div>
          </section>

          <aside className="loh-side">
            <section className="loh-panel" aria-labelledby="loh-tel-title">
              <div className="loh-panel-head">
                <div>
                  <span className="loh-label">Telemetry</span>
                  <h2 id="loh-tel-title">Subsystem Status</h2>
                </div>
                <span className="loh-count is-ok">NOMINAL</span>
              </div>

              <div className="loh-badges">
                <StatusBadge
                  tone="ok"
                  icon={<IconShield />}
                  label="Lander stable"
                  detail="tilt 0.4° · legs locked"
                />
                <StatusBadge
                  tone="ok"
                  icon={<IconDrill />}
                  label="PSR survey active"
                  detail="pass 3 · PSR-9"
                />
                <StatusBadge
                  tone="warn"
                  icon={<IconThermal />}
                  label="Thermal margin"
                  detail={`${telemetry.temp.toFixed(1)} °C external`}
                />
                <StatusBadge
                  tone="ok"
                  icon={<IconSignal />}
                  label="DSN uplink"
                  detail={`${(telemetry.signal / 10).toFixed(1)} dB · 34.2°`}
                />
              </div>

              <dl className="loh-readouts">
                <div>
                  <dt>Solar array</dt>
                  <dd>
                    {telemetry.power.toFixed(0)}
                    <small>W</small>
                  </dd>
                </div>
                <div>
                  <dt>Battery</dt>
                  <dd>
                    {telemetry.battery.toFixed(0)}
                    <small>%</small>
                  </dd>
                </div>
                <div>
                  <dt>Signal delay</dt>
                  <dd>
                    {telemetry.latency.toFixed(2)}
                    <small>s</small>
                  </dd>
                </div>
                <div>
                  <dt>Radiation</dt>
                  <dd>
                    {telemetry.radiation.toFixed(2)}
                    <small>mSv</small>
                  </dd>
                </div>
              </dl>

              <div className="loh-sparkwrap">
                <div className="loh-sparkhead">
                  <span>X-BAND LINK QUALITY</span>
                  <span>{telemetry.signal.toFixed(1)} %</span>
                </div>
                <Sparkline data={history} />
              </div>
            </section>

            <section className="loh-panel loh-logpanel" aria-labelledby="loh-log-title">
              <div className="loh-panel-head">
                <div>
                  <span className="loh-label">Mission Log</span>
                  <h2 id="loh-log-title">Event Feed</h2>
                </div>
              </div>
              <ul className="loh-log" aria-live="polite">
                {log.slice(0, 4).map((entry) => (
                  <li key={entry.id} data-tone={entry.tone}>
                    <span className="loh-log-dot" aria-hidden="true" />
                    <span className="loh-log-clock">{entry.clock}</span>
                    <span className="loh-log-text">{entry.text}</span>
                  </li>
                ))}
              </ul>
            </section>
          </aside>
        </div>

        {/* -------------------------- footer ------------------------- */}
        <footer className="loh-footer">
          <div className="loh-controls">
            <button
              type="button"
              className="loh-btn is-primary"
              onClick={() => dispatch({ type: "toggle" })}
              aria-pressed={running}
            >
              {running ? "❚❚ Pause" : "▶ Resume"}
            </button>

            <div className="loh-speed" role="group" aria-label="Simulation speed">
              {[1, 2, 4].map((value) => (
                <button
                  key={value}
                  type="button"
                  className={`loh-btn ${speed === value ? "is-on" : ""}`}
                  onClick={() => dispatch({ type: "speed", speed: value })}
                  aria-pressed={speed === value}
                >
                  {value}×
                </button>
              ))}
            </div>

            <button
              type="button"
              className="loh-btn"
              onClick={() =>
                dispatch({ type: "reset", day: initialDay, phase: initialPhase })
              }
            >
              ↺ Reset
            </button>
          </div>

          <p className="loh-hint">
            <kbd>Space</kbd> pause · <kbd>1</kbd>/<kbd>2</kbd>/<kbd>4</kbd> speed ·{" "}
            <kbd>R</kbd> reset
          </p>
        </footer>
      </div>
    </div>
  );
}

/* ------------------------------ styles ---------------------------- */

/*
 * MISSIONFORGE — monochrome interface.
 * Every value below is neutral grey (r = g = b).  Emphasis is carried by
 * brightness and opacity, never by hue.  This stylesheet only ever styles the
 * 2D HUD; the Three.js / 3D viewport is a separate colour system and must keep
 * its natural colours (blue oceans, orange plume, gold foil, white ice).
 */
const HUD_CSS = `
.loh {
  --loh-bg: #050505;
  --loh-panel: rgba(14, 14, 14, 0.78);
  --loh-panel-2: rgba(18, 18, 18, 0.72);
  --loh-line: rgba(210, 210, 210, 0.16);
  --loh-line-strong: rgba(210, 210, 210, 0.38);
  --loh-text: #eaeaea;
  --loh-muted: #8a8a8a;
  /* Legacy token names kept for compatibility; all resolve to greys. */
  --loh-cyan: #f2f2f2;   /* primary   */
  --loh-amber: #b9b9b9;  /* secondary */
  --loh-violet: #9a9a9a; /* tertiary  */
  --loh-green: #ffffff;  /* success   */
  --loh-red: #cfcfcf;    /* alert     */
  --loh-mono: ui-monospace, "Cascadia Mono", "SF Mono", Consolas, monospace;
  --loh-sans: "Segoe UI", ui-sans-serif, Roboto, Helvetica, Arial, sans-serif;

  width: 100%;
  max-width: 1080px;
  margin: 0 auto;
  padding: 10px;
  color: var(--loh-text);
  font-family: var(--loh-sans);
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}

.loh *,
.loh *::before,
.loh *::after {
  box-sizing: border-box;
}

.loh-shell {
  position: relative;
  overflow: hidden;
  border: 1px solid var(--loh-line);
  border-radius: 18px;
  padding: 22px 22px 18px;
  background:
    radial-gradient(1200px 420px at 12% -20%, rgba(80, 80, 80, 0.34), transparent 62%),
    radial-gradient(900px 380px at 92% 118%, rgba(62, 62, 62, 0.28), transparent 60%),
    linear-gradient(160deg, rgba(10, 10, 10, 0.97), rgba(7, 7, 7, 0.99));
  box-shadow:
    0 28px 70px rgba(0, 0, 0, 0.55),
    inset 0 1px 0 rgba(255, 255, 255, 0.05),
    inset 0 0 90px rgba(58, 58, 58, 0.08);
}

.loh-shell::before {
  content: "";
  position: absolute;
  inset: 0;
  border-radius: inherit;
  pointer-events: none;
  background-image:
    linear-gradient(rgba(210, 210, 210, 0.05) 1px, transparent 1px),
    linear-gradient(90deg, rgba(210, 210, 210, 0.05) 1px, transparent 1px);
  background-size: 44px 44px;
  mask-image: radial-gradient(circle at 50% 20%, #000 10%, transparent 78%);
}

.loh-glow {
  position: absolute;
  top: -120px;
  right: 12%;
  width: 320px;
  height: 220px;
  background: radial-gradient(circle, rgba(242, 242, 242, 0.16), transparent 65%);
  filter: blur(12px);
  pointer-events: none;
}

.loh-scanlines {
  position: absolute;
  inset: 0;
  pointer-events: none;
  opacity: 0.35;
  background: repeating-linear-gradient(
    to bottom,
    rgba(255, 255, 255, 0.035) 0 1px,
    transparent 1px 3px
  );
  mix-blend-mode: overlay;
}

/* ------------------------------ header ------------------------------ */

.loh-header {
  position: relative;
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  justify-content: space-between;
  gap: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--loh-line);
}

.loh-kicker {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-family: var(--loh-mono);
  font-size: 10px;
  letter-spacing: 0.26em;
  text-transform: uppercase;
  color: var(--loh-cyan);
  opacity: 0.85;
}

.loh-pulse {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--loh-cyan);
  box-shadow: 0 0 0 0 rgba(242, 242, 242, 0.6);
  animation: loh-pulse 2.2s infinite;
}

.loh-title {
  margin: 8px 0 4px;
  font-size: clamp(24px, 3.4vw, 36px);
  font-weight: 600;
  line-height: 1.05;
  letter-spacing: 0.12em;
  color: #f7f7f7;
  text-shadow: 0 0 26px rgba(242, 242, 242, 0.25);
}

.loh-title span {
  display: block;
  margin-top: 6px;
  font-family: var(--loh-mono);
  font-size: 10px;
  font-weight: 500;
  letter-spacing: 0.44em;
  text-transform: uppercase;
  color: var(--loh-cyan);
}

.loh-sub {
  margin: 6px 0 0;
  font-size: 12px;
  letter-spacing: 0.04em;
  color: var(--loh-muted);
}

.loh-dayblock {
  min-width: 290px;
  flex: 0 1 340px;
}

.loh-label {
  display: block;
  font-family: var(--loh-mono);
  font-size: 9.5px;
  letter-spacing: 0.28em;
  text-transform: uppercase;
  color: var(--loh-muted);
}

.loh-dayvalue {
  margin: 6px 0 10px;
  font-family: var(--loh-mono);
  font-size: 13px;
  letter-spacing: 0.16em;
  color: var(--loh-muted);
  font-variant-numeric: tabular-nums;
}

.loh-dayvalue strong {
  font-size: 30px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: #fff;
  text-shadow: 0 0 22px rgba(242, 242, 242, 0.45);
}

.loh-dayvalue em {
  font-style: normal;
  font-size: 14px;
  color: var(--loh-muted);
}

.loh-rail {
  display: flex;
  gap: 3px;
  height: 8px;
  margin-bottom: 10px;
}

.loh-rail span {
  flex: 1;
  border-radius: 1px;
  background: rgba(165, 165, 165, 0.14);
  transition: background 320ms ease, box-shadow 320ms ease;
}

.loh-rail span.is-on {
  background: linear-gradient(180deg, #f0f0f0, #9c9c9c);
  box-shadow: 0 0 10px rgba(242, 242, 242, 0.45);
}

.loh-clockrow {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  font-family: var(--loh-mono);
  font-size: 10px;
  letter-spacing: 0.12em;
  color: var(--loh-muted);
}

.loh-clock {
  font-variant-numeric: tabular-nums;
  color: #b3b3b3;
}

.loh-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  text-transform: uppercase;
  color: var(--loh-amber);
}

.loh-link::before {
  content: "";
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: currentColor;
}

.loh-link.is-live {
  color: var(--loh-green);
}

.loh-link.is-live::before {
  animation: loh-blink 1.6s infinite;
}

/* ------------------------------ phases ------------------------------ */

.loh-phases {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 14px 0 16px;
}

.loh-phase {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 7px 12px;
  border: 1px solid rgba(165, 165, 165, 0.16);
  border-radius: 999px;
  background: rgba(15, 15, 15, 0.6);
  font-family: var(--loh-mono);
  font-size: 9.5px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--loh-muted);
  white-space: nowrap;
}

.loh-phase-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: rgba(165, 165, 165, 0.4);
}

.loh-phase.is-done {
  color: #dedede;
  border-color: rgba(255, 255, 255, 0.28);
  background: rgba(42, 42, 42, 0.24);
}

.loh-phase.is-done .loh-phase-dot {
  background: var(--loh-green);
  box-shadow: 0 0 8px rgba(255, 255, 255, 0.7);
}

.loh-phase.is-active {
  color: #f3f3f3;
  border-color: rgba(242, 242, 242, 0.55);
  background: rgba(45, 45, 45, 0.42);
  box-shadow: 0 0 18px rgba(242, 242, 242, 0.16), inset 0 0 18px rgba(242, 242, 242, 0.08);
}

.loh-phase.is-active .loh-phase-dot {
  background: var(--loh-cyan);
  box-shadow: 0 0 10px var(--loh-cyan);
  animation: loh-blink 1.8s infinite;
}

/* ------------------------------- grid ------------------------------- */

.loh-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.55fr) minmax(0, 1fr);
  gap: 14px;
}

.loh-panel {
  position: relative;
  border: 1px solid var(--loh-line);
  border-radius: 14px;
  padding: 16px;
  background:
    linear-gradient(180deg, rgba(20, 20, 20, 0.72), rgba(11, 11, 11, 0.72));
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
}

.loh-panel::before {
  content: "";
  position: absolute;
  top: 0;
  left: 16px;
  right: 16px;
  height: 1px;
  background: linear-gradient(90deg, transparent, rgba(242, 242, 242, 0.4), transparent);
}

.loh-panel-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 14px;
}

.loh-panel-head h2 {
  margin: 4px 0 0;
  font-size: 16px;
  font-weight: 600;
  letter-spacing: 0.03em;
  color: #f2f2f2;
}

.loh-count {
  flex: none;
  padding: 4px 8px;
  border: 1px solid rgba(185, 185, 185, 0.35);
  border-radius: 4px;
  background: rgba(185, 185, 185, 0.08);
  font-family: var(--loh-mono);
  font-size: 9px;
  letter-spacing: 0.16em;
  color: var(--loh-amber);
}

.loh-count.is-ok {
  border-color: rgba(255, 255, 255, 0.35);
  background: rgba(255, 255, 255, 0.08);
  color: var(--loh-green);
}

/* ------------------------------ operations ------------------------------ */

.loh-oplist {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.loh-op {
  --tone: var(--loh-cyan);
  --tone-soft: rgba(242, 242, 242, 0.16);
  position: relative;
  padding-left: 12px;
}

.loh-op::before {
  content: "";
  position: absolute;
  left: 0;
  top: 4px;
  bottom: 4px;
  width: 2px;
  border-radius: 2px;
  background: linear-gradient(180deg, var(--tone), transparent);
  opacity: 0.75;
}

.loh-op[data-tone="amber"] {
  --tone: var(--loh-amber);
  --tone-soft: rgba(185, 185, 185, 0.16);
}

.loh-op[data-tone="violet"] {
  --tone: var(--loh-violet);
  --tone-soft: rgba(150, 150, 150, 0.16);
}

.loh-op[data-tone="green"] {
  --tone: var(--loh-green);
  --tone-soft: rgba(255, 255, 255, 0.16);
}

.loh-op-head {
  display: flex;
  align-items: baseline;
  gap: 8px;
  margin-bottom: 7px;
}

.loh-op-code {
  font-family: var(--loh-mono);
  font-size: 9px;
  letter-spacing: 0.14em;
  color: var(--tone);
  opacity: 0.9;
}

.loh-op-label {
  margin: 0;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.015em;
  color: #e6e6e6;
}

.loh-op-pct {
  margin-left: auto;
  font-family: var(--loh-mono);
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  color: var(--tone);
}

.loh-op-pct small {
  margin-left: 1px;
  font-size: 9px;
  opacity: 0.7;
}

.loh-bar {
  position: relative;
  height: 10px;
  overflow: hidden;
  border: 1px solid rgba(165, 165, 165, 0.16);
  border-radius: 999px;
  background: rgba(6, 6, 6, 0.85);
  box-shadow: inset 0 1px 4px rgba(0, 0, 0, 0.6);
}

.loh-bar-fill {
  position: absolute;
  inset: 0 auto 0 0;
  width: 0;
  border-radius: inherit;
  background: linear-gradient(90deg, var(--tone-soft), var(--tone));
  box-shadow: 0 0 14px var(--tone-soft);
  transition: width 280ms linear;
}

.loh-bar-fill::after {
  content: "";
  position: absolute;
  inset: 0;
  background: linear-gradient(
    100deg,
    transparent 20%,
    rgba(255, 255, 255, 0.5) 50%,
    transparent 80%
  );
  transform: translateX(-100%);
  animation: loh-sweep 2.6s linear infinite;
  opacity: 0.55;
}

.loh-bar-ticks {
  position: absolute;
  inset: 0;
  opacity: 0.3;
  background-image: repeating-linear-gradient(
    90deg,
    transparent 0 9px,
    rgba(5, 5, 5, 0.9) 9px 11px
  );
}

.loh-op.is-done .loh-bar-fill::after {
  animation: none;
  opacity: 0;
}

.loh-op-meta {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  margin-top: 6px;
  font-family: var(--loh-mono);
  font-size: 9.5px;
  letter-spacing: 0.06em;
}

.loh-op-detail {
  color: var(--loh-muted);
}

.loh-op-tag {
  flex: none;
  color: var(--tone);
}

.loh-op-tag.is-complete {
  color: var(--loh-green);
  letter-spacing: 0.18em;
}

.loh-ops-foot {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 18px;
  margin-top: 18px;
  padding-top: 12px;
  border-top: 1px dashed rgba(165, 165, 165, 0.16);
  font-family: var(--loh-mono);
  font-size: 9px;
  letter-spacing: 0.12em;
  color: var(--loh-muted);
}

.loh-ops-foot b {
  color: #c4c4c4;
  font-weight: 500;
}

/* ------------------------------ side column ------------------------------ */

.loh-side {
  display: flex;
  flex-direction: column;
  gap: 14px;
  min-width: 0;
}

.loh-badges {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.loh-badge {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 9px;
  border: 1px solid rgba(165, 165, 165, 0.14);
  border-radius: 9px;
  background: rgba(13, 13, 13, 0.7);
}

.loh-badge[data-tone="ok"] {
  border-color: rgba(255, 255, 255, 0.22);
}

.loh-badge[data-tone="warn"] {
  border-color: rgba(185, 185, 185, 0.3);
}

.loh-badge-icon {
  display: grid;
  place-items: center;
  flex: none;
  width: 27px;
  height: 27px;
  border-radius: 7px;
  background: rgba(255, 255, 255, 0.1);
  color: var(--loh-green);
}

.loh-badge[data-tone="warn"] .loh-badge-icon {
  background: rgba(185, 185, 185, 0.12);
  color: var(--loh-amber);
}

.loh-badge-icon svg {
  width: 15px;
  height: 15px;
}

.loh-badge-copy {
  display: flex;
  flex-direction: column;
  min-width: 0;
}

.loh-badge-label {
  font-size: 10.5px;
  font-weight: 600;
  letter-spacing: 0.02em;
  color: #e6e6e6;
}

.loh-badge-detail {
  overflow: hidden;
  font-family: var(--loh-mono);
  font-size: 8.5px;
  letter-spacing: 0.04em;
  color: var(--loh-muted);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.loh-readouts {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1px;
  margin: 12px 0;
  border: 1px solid rgba(165, 165, 165, 0.12);
  border-radius: 9px;
  overflow: hidden;
  background: rgba(165, 165, 165, 0.12);
}

.loh-readouts > div {
  padding: 9px 11px;
  background: rgba(11, 11, 11, 0.94);
}

.loh-readouts dt {
  margin-bottom: 4px;
  font-family: var(--loh-mono);
  font-size: 8.5px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: var(--loh-muted);
}

.loh-readouts dd {
  margin: 0;
  font-family: var(--loh-mono);
  font-size: 17px;
  font-variant-numeric: tabular-nums;
  color: #f1f1f1;
}

.loh-readouts dd small {
  margin-left: 3px;
  font-size: 9px;
  color: var(--loh-muted);
}

.loh-sparkwrap {
  padding-top: 10px;
  border-top: 1px solid rgba(165, 165, 165, 0.12);
}

.loh-sparkhead {
  display: flex;
  justify-content: space-between;
  margin-bottom: 4px;
  font-family: var(--loh-mono);
  font-size: 8.5px;
  letter-spacing: 0.16em;
  color: var(--loh-muted);
}

.loh-spark {
  display: block;
  width: 100%;
  height: 46px;
  overflow: visible;
}

.loh-spark-line {
  fill: none;
  stroke: var(--loh-cyan);
  stroke-width: 1.4;
  vector-effect: non-scaling-stroke;
  filter: drop-shadow(0 0 4px rgba(242, 242, 242, 0.8));
}

.loh-spark-area {
  fill: url(#loh-spark-fill);
  stroke: none;
}

/* -------------------------------- log -------------------------------- */

.loh-logpanel {
  flex: 1;
}

.loh-log {
  display: flex;
  flex-direction: column;
  gap: 9px;
  max-height: 128px;
  margin: 0;
  padding: 0;
  overflow-y: auto;
  list-style: none;
  scrollbar-width: thin;
  scrollbar-color: rgba(242, 242, 242, 0.25) transparent;
}

.loh-log li {
  display: grid;
  grid-template-columns: 6px auto 1fr;
  align-items: baseline;
  gap: 8px;
  font-size: 10px;
  line-height: 1.35;
}

.loh-log-dot {
  width: 5px;
  height: 5px;
  border-radius: 50%;
  background: var(--loh-cyan);
  transform: translateY(-1px);
}

.loh-log li[data-tone="success"] .loh-log-dot {
  background: var(--loh-green);
  box-shadow: 0 0 6px rgba(255, 255, 255, 0.8);
}

.loh-log-clock {
  font-family: var(--loh-mono);
  font-size: 8.5px;
  letter-spacing: 0.04em;
  color: #7d7d7d;
  white-space: nowrap;
}

.loh-log-text {
  color: #bcbcbc;
}

/* ------------------------------- footer ------------------------------- */

.loh-footer {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 16px;
  padding-top: 14px;
  border-top: 1px solid var(--loh-line);
}

.loh-controls {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.loh-btn {
  padding: 8px 13px;
  border: 1px solid rgba(165, 165, 165, 0.2);
  border-radius: 8px;
  background: rgba(16, 16, 16, 0.85);
  color: #bfbfbf;
  font-family: var(--loh-mono);
  font-size: 10px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  cursor: pointer;
  transition: border-color 160ms ease, background 160ms ease, color 160ms ease,
    box-shadow 160ms ease;
}

.loh-btn:hover {
  border-color: rgba(242, 242, 242, 0.45);
  color: #f5f5f5;
}

.loh-btn:focus-visible {
  outline: 2px solid var(--loh-cyan);
  outline-offset: 2px;
}

.loh-btn.is-primary {
  border-color: rgba(242, 242, 242, 0.5);
  background: rgba(43, 43, 43, 0.5);
  color: #f4f4f4;
  box-shadow: 0 0 16px rgba(242, 242, 242, 0.12);
}

.loh-btn.is-on {
  border-color: rgba(242, 242, 242, 0.55);
  background: rgba(55, 55, 55, 0.55);
  color: #fff;
}

.loh-speed {
  display: flex;
  gap: 4px;
  padding: 3px;
  border: 1px solid rgba(165, 165, 165, 0.14);
  border-radius: 10px;
  background: rgba(9, 9, 9, 0.7);
}

.loh-speed .loh-btn {
  padding: 5px 9px;
  border-color: transparent;
  background: transparent;
}

.loh-speed .loh-btn.is-on {
  border-color: rgba(242, 242, 242, 0.45);
  background: rgba(55, 55, 55, 0.55);
}

.loh-hint {
  margin: 0;
  font-family: var(--loh-mono);
  font-size: 8.5px;
  letter-spacing: 0.08em;
  color: #6f6f6f;
}

.loh-hint kbd {
  padding: 1px 4px;
  border: 1px solid rgba(165, 165, 165, 0.22);
  border-radius: 3px;
  background: rgba(18, 18, 18, 0.9);
  color: #a8a8a8;
  font-family: inherit;
  font-size: inherit;
}

/* ------------------------------ animations ------------------------------ */

@keyframes loh-pulse {
  0% { box-shadow: 0 0 0 0 rgba(242, 242, 242, 0.55); }
  70% { box-shadow: 0 0 0 8px rgba(242, 242, 242, 0); }
  100% { box-shadow: 0 0 0 0 rgba(242, 242, 242, 0); }
}

@keyframes loh-blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.35; }
}

@keyframes loh-sweep {
  0% { transform: translateX(-100%); }
  100% { transform: translateX(100%); }
}

/* ------------------------------ responsive ------------------------------ */

@media (max-width: 900px) {
  .loh-grid {
    grid-template-columns: 1fr;
  }

  .loh-badges {
    grid-template-columns: 1fr 1fr;
  }

  .loh-dayblock {
    flex: 1 1 100%;
    min-width: 0;
  }
}

@media (max-width: 560px) {
  .loh-shell {
    padding: 16px 14px 14px;
  }

  .loh-title {
    font-size: 22px;
  }

  .loh-badges,
  .loh-readouts {
    grid-template-columns: 1fr;
  }

  .loh-op-label {
    font-size: 12px;
  }

  .loh-hint {
    display: none;
  }
}

@media (prefers-reduced-motion: reduce) {
  .loh *,
  .loh *::before,
  .loh *::after {
    animation-duration: 0.001ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.001ms !important;
  }
}
`;
