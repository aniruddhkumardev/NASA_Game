"""
Shared game state — single object passed between all screens
"""
import random
from src.constants import RANDOM_EVENTS, DIFFICULTIES, SCENARIOS


class Player:
    def __init__(self, idx, name, role):
        self.idx   = idx
        self.name  = name
        self.role  = role
        self.score = 0


class MissionState:
    """Everything the player has chosen / resources consumed."""
    def __init__(self):
        self.reset()

    def reset(self):
        self.scenario        = None   # dict from SCENARIOS
        self.spacecraft_bus  = None   # dict
        self.power_system    = None   # dict
        self.instruments     = []     # list of dicts
        self.orbit           = None   # dict
        self.launch_vehicle  = None   # dict
        self.difficulty      = "Engineer"

        # computed totals
        self.total_mass      = 0
        self.total_power     = 0
        self.total_cost      = 0   # M USD
        self.total_data      = 0   # GB/day demand
        self.total_comms     = 0   # Mbps available
        self.total_science   = 0   # science score

        # simulation results
        self.sim_events      = []
        self.final_score     = 0
        self.mission_success = False
        self.bonus_achieved  = []
        self.sim_log         = []

    def compute_totals(self):
        """Recalculate all resource totals from current selections."""
        sc = self.spacecraft_bus or {}
        ps = self.power_system or {}
        sc_mass  = sc.get("mass", 0)
        ps_mass  = ps.get("mass", 0)
        inst_mass  = sum(i["mass"]  for i in self.instruments)
        inst_power = sum(i["power"] for i in self.instruments)
        inst_cost  = sum(i["cost"]  for i in self.instruments)
        inst_data  = sum(i["data"]  for i in self.instruments)
        inst_sci   = sum(i["science"] for i in self.instruments)

        orb = self.orbit or {}
        lv  = self.launch_vehicle or {}

        self.total_mass   = sc_mass + ps_mass + inst_mass + orb.get("mass_penalty", 0)
        self.total_power  = ps.get("power_gen", 0) - inst_power - sc.get("power", 0)
        self.total_cost   = (sc.get("cost", 0) + ps.get("cost", 0)
                             + inst_cost + orb.get("cost", 0) + lv.get("cost", 0))
        self.total_data   = inst_data
        self.total_comms  = sc.get("comms", 0) * orb.get("comms_boost", 1.0)
        self.total_science = inst_sci

    def get_resource_fractions(self):
        """Return (used, limit) fractions 0..1 for each resource."""
        sc = self.scenario or {}
        budget_frac  = min(self.total_cost   / max(sc.get("budget_limit", 600), 1), 1.0)
        mass_frac    = min(self.total_mass   / max(sc.get("mass_limit",  2200), 1), 1.0)
        power_margin = self.total_power  # positive = surplus, negative = deficit
        data_frac    = min(self.total_data   / max(sc.get("data_limit",   500), 1), 1.0)
        comms_frac   = min(self.total_comms  / max(sc.get("comms_limit",  200), 1), 1.0)
        return {
            "budget": budget_frac,
            "mass":   mass_frac,
            "power":  power_margin,
            "data":   data_frac,
            "comms":  comms_frac,
        }

    def validate(self):
        """Return list of warning/error strings. Empty = all good."""
        issues = []
        sc  = self.scenario or {}
        lv  = self.launch_vehicle or {}
        orb = self.orbit or {}

        if not self.spacecraft_bus:
            issues.append("⚠  No spacecraft bus selected.")
        if not self.power_system:
            issues.append("⚠  No power system selected.")
        if not self.instruments:
            issues.append("⚠  No scientific instruments selected.")
        if not self.orbit:
            issues.append("⚠  No orbit selected.")
        if not self.launch_vehicle:
            issues.append("⚠  No launch vehicle selected.")

        if self.total_cost > sc.get("budget_limit", 9999) * DIFFICULTIES[self.difficulty]["budget_mult"]:
            issues.append("💸  Over budget! Reduce cost or choose easier difficulty.")
        if self.total_mass > sc.get("mass_limit", 9999):
            issues.append("⚖  Spacecraft too heavy for mass budget.")
        if lv and self.total_mass > lv.get("capacity", 9999):
            issues.append("🚀  Launch vehicle can't lift this payload!")
        if self.total_power < 0:
            issues.append("⚡  Power deficit! Instruments draw more than generated.")
        if self.total_data > sc.get("data_limit", 9999):
            issues.append("📡  Data rate exceeds downlink capacity.")
        if sc.get("target") and lv:
            target = sc.get("target")
            if target not in lv.get("targets", []):
                issues.append(f"🚀  Launch vehicle cannot reach {target}.")

        # deep space + solar panels
        ps = self.power_system or {}
        if sc.get("target") in ["Asteroid Belt", "Jupiter"] and not ps.get("works_far"):
            issues.append("☀  Solar panels too weak at this distance. Use RTG.")

        return issues

    def run_simulation(self):
        """Run the mission simulation, apply random events, compute final score."""
        self.sim_log    = []
        self.sim_events = []
        sc   = self.scenario or {}
        diff = DIFFICULTIES.get(self.difficulty, DIFFICULTIES["Engineer"])
        n_events = diff["events"]

        self.sim_log.append(f"T+0:00  Mission launch confirmed. Target: {sc.get('target','?')}")
        self.sim_log.append(f"T+0:12  Spacecraft separated from launch vehicle successfully.")
        self.sim_log.append(f"T+1:00  Solar panels / power systems deployed.")

        # pick random events
        pool   = random.sample(RANDOM_EVENTS, min(n_events, len(RANDOM_EVENTS)))
        sci_delta  = 0
        pow_delta  = 0
        cost_delta = 0
        data_delta = 0
        comms_delta= 0

        ps_id = (self.power_system or {}).get("id", "")

        for i, ev in enumerate(pool):
            day = random.randint(10, 300)
            self.sim_events.append(ev)
            self.sim_log.append(f"Day {day:>3}:  [{ev['icon']}] {ev['name']} — {ev['desc']}")
            eff = ev.get("effect", {})
            mit = ev.get("mitigation")
            mitigated = mit and mit in ps_id

            sci_delta   += eff.get("science", 0) * (0.3 if mitigated else 1)
            pow_delta   += eff.get("power",   0) * (0.3 if mitigated else 1)
            cost_delta  += eff.get("budget",  0)
            data_delta  += eff.get("data",    0)
            comms_delta += eff.get("comms",   0)
            if mitigated:
                self.sim_log.append(f"          ↳ RTG power system mitigated the power impact!")

        self.sim_log.append("─" * 55)
        self.sim_log.append("Cruise phase complete. Approaching target body.")
        self.sim_log.append("All instruments nominal. Science operations begin.")

        # --- scoring ---
        base_science  = max(0, self.total_science + sci_delta)
        power_ok      = (self.total_power + pow_delta) >= 0
        budget_limit  = sc.get("budget_limit", 600) * diff["budget_mult"]
        under_budget  = (self.total_cost - cost_delta) <= budget_limit
        comms_ok      = max(0, self.total_comms + comms_delta) >= 50
        min_sci       = sc.get("min_science", 50)

        # bonus objectives
        self.bonus_achieved = []
        for b in sc.get("bonus_objectives", []):
            # check if relevant instruments are present
            inst_ids = [i["id"] for i in self.instruments]
            achieved = False
            if "water" in b.lower() and any(x in inst_ids for x in ["radar", "spectrometer", "mass_spec"]):
                achieved = True
            elif "map" in b.lower() or "surface" in b.lower():
                if "camera_hires" in inst_ids or "lidar" in inst_ids:
                    achieved = True
            elif "subsurface" in b.lower():
                if "radar" in inst_ids or "seismometer" in inst_ids:
                    achieved = True
            elif "sample" in b.lower():
                if "mass_spec" in inst_ids:
                    achieved = True
            elif "magnetic" in b.lower() or "magnetosphere" in b.lower():
                if "magnetometer" in inst_ids or "plasma_analyzer" in inst_ids:
                    achieved = True
            elif "radiation" in b.lower():
                if "plasma_analyzer" in inst_ids:
                    achieved = True
            elif "volcano" in b.lower():
                if "camera_hires" in inst_ids or "spectrometer" in inst_ids:
                    achieved = True
            elif "weather" in b.lower():
                if "spectrometer" in inst_ids or "camera_wide" in inst_ids:
                    achieved = True
            elif "gravity" in b.lower() or "geologic" in b.lower():
                if "seismometer" in inst_ids or "radio_science" in inst_ids:
                    achieved = True
            elif "orbit" in b.lower():
                achieved = True  # if they chose an orbit, they orbit
            elif "ocean" in b.lower():
                if "radar" in inst_ids or "mass_spec" in inst_ids:
                    achieved = True
            if achieved:
                self.bonus_achieved.append(b)

        # base score
        score = int(base_science * 8)
        if power_ok:    score += 150
        if under_budget: score += 200
        if comms_ok:    score += 100
        score += len(self.bonus_achieved) * 80

        # bus reliability modifier
        bus_rel = (self.spacecraft_bus or {}).get("reliability", 0.9)
        lv_rel  = (self.launch_vehicle or {}).get("reliability", 0.9)
        overall_rel = bus_rel * lv_rel
        score = int(score * overall_rel)

        # success check
        self.mission_success = (
            base_science >= min_sci
            and power_ok
            and lv_rel * bus_rel > 0.75
        )

        self.final_score = max(0, score)

        status = "SUCCESS ✓" if self.mission_success else "PARTIAL FAILURE ✗"
        self.sim_log.append("")
        self.sim_log.append(f"Mission Status: {status}")
        self.sim_log.append(f"Science Score:  {base_science:.0f}")
        self.sim_log.append(f"Final Score:    {self.final_score} pts")

        return self.final_score


class GameState:
    def __init__(self):
        self.phase         = 0           # index into PHASES
        self.players       = []          # list of Player
        self.num_players   = 1
        self.current_player= 0           # whose turn it is in multi-player steps
        self.mission       = MissionState()
        self.high_scores   = []          # list of (name, score, scenario)

    def add_player(self, name, role):
        p = Player(len(self.players), name, role)
        self.players.append(p)
        return p

    def next_phase(self):
        self.phase += 1
        # advance which player drives (cyclic)
        if self.players:
            self.current_player = self.phase % len(self.players)

    def prev_phase(self):
        self.phase = max(1, self.phase - 1)

    def active_player(self):
        if not self.players:
            return None
        return self.players[self.current_player % len(self.players)]

    def reset_mission(self):
        self.phase = 1
        self.mission.reset()
        self.players = []
        self.current_player = 0
