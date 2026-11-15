"""
Spacecraft Bus selection screen
"""
import pygame
from src.screens.base import BaseScreen
from src.constants import C, WIDTH, HEIGHT, SPACECRAFT_BUS
from src.ui import Button, SelectCard, StarField, draw_text, rounded_rect, draw_multiline


class SpacecraftBusScreen(BaseScreen):
    def __init__(self, gs, surf):
        super().__init__(gs, surf)
        self.stars = StarField(180)

        # 4 cards in a row
        cw, ch = (WIDTH - 60) // 4 - 8, 280
        self.cards = []
        for i, bus in enumerate(SPACECRAFT_BUS):
            x = 20 + i * (cw + 10)
            card = SelectCard(
                pygame.Rect(x, 115, cw, ch),
                bus, self.fonts.body, self.fonts.small
            )
            if gs.mission.spacecraft_bus and gs.mission.spacecraft_bus["id"] == bus["id"]:
                card.selected = True
            self.cards.append(card)

        self.btn_next = Button((WIDTH - 200, HEIGHT - 68, 180, 48),
                               "NEXT", C["btn_green"], C["btn_green_h"], self.fonts.heading, icon="→")
        self.btn_back = Button((20, HEIGHT - 68, 120, 48),
                               "BACK", C["btn_normal"], C["btn_hover"], self.fonts.body)
        self.next_screen = None

    def _selected_bus(self):
        for c in self.cards:
            if c.selected:
                return c.data
        return None

    def handle_event(self, event):
        for c in self.cards:
            if c.handle_event(event):
                # deselect others
                for other in self.cards:
                    if other is not c:
                        other.selected = False

        if self.btn_next.handle_event(event):
            bus = self._selected_bus()
            if bus:
                self.gs.mission.spacecraft_bus = bus
                self.gs.mission.compute_totals()
                self.next_screen = "power_system"

        if self.btn_back.handle_event(event):
            self.next_screen = "scenario"

    def draw(self):
        self.surface.fill(C["bg_dark"])
        self.stars.draw(self.surface)
        self.draw_header("Space Mission Design",
                         f"Target: {(self.gs.mission.scenario or {}).get('target','?')}",
                         "Phase 3 / 9")
        self.draw_resource_hud(72)

        draw_text(self.surface, "CHOOSE SPACECRAFT BUS",
                  WIDTH//2, 82, self.fonts.heading, C["white"], center=True)
        draw_text(self.surface, "The bus is the main satellite body — determines mass, power, comms, and cost limits.",
                  WIDTH//2, 105, self.fonts.small, C["dim"], center=True)

        for c in self.cards:
            c.draw(self.surface)

        # detail panel for selected
        bus = self._selected_bus()
        if bus:
            self._draw_detail(bus)

        self.btn_next.disabled = bus is None
        self.btn_next.draw(self.surface)
        self.btn_back.draw(self.surface)

    def _draw_detail(self, bus):
        panel = pygame.Rect(20, 400, WIDTH - 40, 195)
        rounded_rect(self.surface, panel, C["bg_panel"], 12,
                     border=1, border_color=bus["color"])

        draw_text(self.surface, bus["name"], panel.left + 20, panel.top + 14,
                  self.fonts.heading, bus["color"])

        col_w = (panel.width - 40) // 3
        cols = [
            [("Structural Mass",  f"{bus['mass']} kg"),
             ("Comm Bandwidth",   f"{bus['comms']} Mbps"),
             ("Power Draw",       f"{bus['power']} W")],
            [("Development Cost", f"${bus['cost']}M"),
             ("Data Storage",     f"{bus['data']} GB/day"),
             ("Reliability",      f"{int(bus['reliability']*100)}%")],
        ]
        for ci, col_data in enumerate(cols):
            x = panel.left + 20 + ci * (col_w + 10)
            for j, (k, v) in enumerate(col_data):
                y = panel.top + 50 + j * 38
                draw_text(self.surface, k, x, y, self.fonts.small, C["dim"])
                draw_text(self.surface, v, x, y + 18, self.fonts.body, C["white"])

        # tip
        tips = {
            "cubesat":   "⚠  Very limited — good for Earth orbit only. Cannot carry heavy instruments.",
            "small_sat": "✓  Good for simple, focused missions. Easy to fit on small rockets.",
            "medium_bus":"✓  Most real-world missions use this class. Best trade-off.",
            "large_bus": "✓  Flagship bus. Maximum instruments but needs a heavy launcher.",
        }
        draw_text(self.surface, tips.get(bus["id"], ""), panel.left + col_w * 2 + 30,
                  panel.top + 50, self.fonts.small, C["grey"])
