"""
Base screen class and font manager
"""
import pygame
from src.constants import C, WIDTH, HEIGHT


class FontManager:
    _instance = None

    @classmethod
    def get(cls):
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    def __init__(self):
        pygame.font.init()
        # Try system fonts, fall back to default
        def load(name, size):
            f = pygame.font.SysFont(name, size)
            return f if f else pygame.font.Font(None, size)

        self.title_xl = load("segoeui", 52)
        self.title    = load("segoeui", 36)
        self.heading  = load("segoeui", 24)
        self.body     = load("segoeui", 18)
        self.small    = load("segoeui", 14)
        self.tiny     = load("segoeui", 12)
        self.mono     = load("consolas", 16)
        self.mono_sm  = load("consolas", 13)


class BaseScreen:
    def __init__(self, game_state, screen_surface):
        self.gs      = game_state
        self.surface = screen_surface
        self.fonts   = FontManager.get()
        self._buttons = []

    def handle_event(self, event):
        pass

    def update(self, dt):
        pass

    def draw(self):
        pass

    def draw_header(self, title, subtitle=None, phase_text=None):
        """Draw top navigation bar."""
        from src.ui import draw_text, rounded_rect
        h = 64
        header_rect = pygame.Rect(0, 0, WIDTH, h)
        pygame.draw.rect(self.surface, C["bg_header"], header_rect)
        pygame.draw.line(self.surface, C["border"], (0, h), (WIDTH, h), 1)

        # Title
        draw_text(self.surface, title, 24, 16, self.fonts.heading, C["cyan"])
        if subtitle:
            draw_text(self.surface, subtitle, 24, 40, self.fonts.small, C["dim"])

        # Phase indicator
        if phase_text:
            draw_text(self.surface, phase_text,
                      WIDTH - 24, 24, self.fonts.body, C["grey"], right=True)

        # Active player indicator
        ap = self.gs.active_player()
        if ap:
            from src.constants import ROLE_COLORS
            col = ROLE_COLORS[ap.idx % len(ROLE_COLORS)]
            label = f"🎮  {ap.name}  [{ap.role}]"
            draw_text(self.surface, label,
                      WIDTH // 2, 22, self.fonts.body, col, center=True)

    def draw_resource_hud(self, y=70):
        """Draw compact resource bars across the top of the content area."""
        from src.ui import draw_text, rounded_rect
        ms = self.gs.mission
        sc = ms.scenario or {}
        ms.compute_totals()

        budget_lim = sc.get("budget_limit", 600)
        mass_lim   = sc.get("mass_limit",  2200)
        data_lim   = sc.get("data_limit",   500)
        comms_lim  = sc.get("comms_limit",  200)

        bars = [
            ("💰 Budget",  ms.total_cost,  budget_lim, C["bar_budget"], False),
            ("⚖ Mass",    ms.total_mass,  mass_lim,   C["bar_mass"],   False),
            ("⚡ Power",   ms.total_power, 500,        C["bar_power"],  True),
            ("📊 Data",    ms.total_data,  data_lim,   C["bar_data"],   False),
            ("📡 Comms",   ms.total_comms, comms_lim,  C["bar_comms"],  False),
        ]
        bw = (WIDTH - 40) // len(bars) - 8
        for i, (label, val, lim, col, inv) in enumerate(bars):
            bx = 20 + i * (bw + 8)
            # label + value
            disp = (f"{'+' if val >= 0 else ''}{val:.0f} W" if inv
                    else f"${val:.0f}M / ${lim}M" if "Budget" in label
                    else f"{val:.0f} / {lim}")
            val_col = C["red"] if (inv and val < 0) else \
                      C["orange"] if (not inv and val > lim * 0.9) else col

            draw_text(self.surface, label, bx, y, self.fonts.tiny, C["dim"])
            draw_text(self.surface, disp, bx + bw, y, self.fonts.tiny, val_col, right=True)

            # bar
            bar_rect = pygame.Rect(bx, y + 16, bw, 8)
            pygame.draw.rect(self.surface, C["bar_bg"], bar_rect, border_radius=4)
            if inv:
                frac = min(1, abs(val) / 500)
                fill_col = C["green"] if val >= 0 else C["red"]
            else:
                frac = min(1, val / max(lim, 1))
                fill_col = C["red"] if frac > 0.95 else C["orange"] if frac > 0.8 else col
            fw = int(bw * frac)
            if fw > 0:
                pygame.draw.rect(self.surface, fill_col,
                                 pygame.Rect(bx, y + 16, fw, 8), border_radius=4)
            pygame.draw.rect(self.surface, C["border"], bar_rect, 1, border_radius=4)
