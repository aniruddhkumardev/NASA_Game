"""
Scenario Selection Screen
"""
import pygame
import math
from src.screens.base import BaseScreen
from src.constants import C, WIDTH, HEIGHT, SCENARIOS, DIFFICULTIES
from src.ui import Button, StarField, draw_text, rounded_rect, draw_multiline


class ScenarioSelectScreen(BaseScreen):
    def __init__(self, gs, surf):
        super().__init__(gs, surf)
        self.stars      = StarField(200)
        self.selected   = None
        self.t          = 0

        # 4 cards layout
        card_w  = (WIDTH - 80) // 4 - 10
        card_h  = 400
        top     = 110
        self.cards = []
        for i, sc in enumerate(SCENARIOS):
            x = 30 + i * (card_w + 12)
            self.cards.append({
                "rect": pygame.Rect(x, top, card_w, card_h),
                "data": sc,
                "hovered": False,
            })

        self.btn_next = Button((WIDTH - 220, HEIGHT - 72, 200, 50),
                               "SELECT & CONTINUE", C["btn_green"], C["btn_green_h"],
                               self.fonts.body, icon="→")
        self.btn_back = Button((20, HEIGHT - 72, 120, 50),
                               "BACK", C["btn_normal"], C["btn_hover"], self.fonts.body)
        self.next_screen = None

    def handle_event(self, event):
        if event.type == pygame.MOUSEMOTION:
            for c in self.cards:
                c["hovered"] = c["rect"].collidepoint(event.pos)

        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            for c in self.cards:
                if c["rect"].collidepoint(event.pos):
                    self.selected = c["data"]

        if self.btn_next.handle_event(event):
            if self.selected:
                self.gs.mission.scenario = self.selected
                self.next_screen = "spacecraft_bus"

        if self.btn_back.handle_event(event):
            self.next_screen = "player_setup"

    def update(self, dt):
        self.t += dt

    def draw(self):
        self.surface.fill(C["bg_dark"])
        self.stars.draw(self.surface)
        self.draw_header("Space Mission Design", "Step 2 — Choose Your Mission", "Phase 2 / 9")

        draw_text(self.surface, "SELECT MISSION SCENARIO",
                  WIDTH//2, 72, self.fonts.heading, C["cyan"], center=True)

        diff     = self.gs.mission.difficulty
        diff_col = DIFFICULTIES.get(diff, {}).get("color", C["white"])
        draw_text(self.surface, f"Difficulty: {diff}",
                  WIDTH - 30, 72, self.fonts.small, diff_col, right=True)

        for c in self.cards:
            self._draw_card(c)

        # bottom: confirm button
        if self.selected:
            lbl = f"✓  {self.selected['name']} selected — click to continue"
            draw_text(self.surface, lbl, WIDTH//2, HEIGHT - 78,
                      self.fonts.body, self.selected["color"], center=True)
        else:
            draw_text(self.surface, "Click a mission card to select",
                      WIDTH//2, HEIGHT - 78, self.fonts.body, C["dim"], center=True)

        self.btn_next.disabled = self.selected is None
        self.btn_next.draw(self.surface)
        self.btn_back.draw(self.surface)

    def _draw_card(self, c):
        rect = c["rect"]
        data = c["data"]
        sel  = self.selected and self.selected["id"] == data["id"]
        hov  = c["hovered"]
        col  = data["color"]

        bg = C["bg_card_hl"] if sel else (25, 36, 82) if hov else C["bg_card"]
        rounded_rect(self.surface, rect, bg, 14,
                     border=3 if sel else 1,
                     border_color=col if (sel or hov) else C["border"])

        if sel:
            # animated glow
            glow_a = int(40 + 25 * math.sin(self.t * 3))
            glow_surf = pygame.Surface((rect.width + 20, rect.height + 20), pygame.SRCALPHA)
            pygame.draw.rect(glow_surf, (*col, glow_a),
                             (0, 0, rect.width + 20, rect.height + 20), border_radius=18)
            self.surface.blit(glow_surf, (rect.x - 10, rect.y - 10),
                              special_flags=pygame.BLEND_ALPHA_SDL2)

        # planet icon (big emoji-style text)
        icon_y = rect.top + 22
        draw_text(self.surface, data["icon"], rect.centerx, icon_y,
                  self.fonts.title_xl, col, center=True)

        # name
        draw_text(self.surface, data["name"], rect.centerx, icon_y + 68,
                  self.fonts.body, C["white"], center=True)

        # difficulty badge
        diff_col = {
            "Easy":   C["green"],
            "Medium": C["yellow"],
            "Hard":   C["orange"],
            "Expert": C["red"],
        }.get(data["difficulty"], C["grey"])
        badge_text = data["difficulty"]
        btw = self.fonts.small.size(badge_text)[0] + 16
        badge_rect = pygame.Rect(rect.centerx - btw//2, icon_y + 92, btw, 22)
        rounded_rect(self.surface, badge_rect, (*diff_col, 40), 6)
        pygame.draw.rect(self.surface, diff_col, badge_rect, 1, border_radius=6)
        draw_text(self.surface, badge_text, badge_rect.centerx,
                  badge_rect.top + 3, self.fonts.small, diff_col, center=True)

        # description
        draw_multiline(self.surface, data["description"],
                       rect.left + 12, icon_y + 122,
                       self.fonts.small, C["grey"],
                       max_width=rect.width - 24)

        # separator
        sep_y = icon_y + 230
        pygame.draw.line(self.surface, C["border"],
                         (rect.left + 10, sep_y), (rect.right - 10, sep_y), 1)

        # limits
        lims = [
            ("💰 Budget",  f"${data['budget_limit']}M"),
            ("⚖ Mass",    f"{data['mass_limit']} kg"),
            ("⚡ Power",   f"{data['power_limit']} W"),
            ("📊 Data",    f"{data['data_limit']} GB/d"),
            ("📡 Comms",   f"{data['comms_limit']} Mbps"),
        ]
        y = sep_y + 12
        for lbl, val in lims:
            draw_text(self.surface, lbl, rect.left + 12, y, self.fonts.tiny, C["dim"])
            draw_text(self.surface, val, rect.right - 12, y, self.fonts.tiny, col, right=True)
            y += 20

        # bonus objectives
        y += 6
        draw_text(self.surface, "Bonus Objectives:", rect.left + 12, y,
                  self.fonts.tiny, C["yellow"])
        y += 18
        for b in data.get("bonus_objectives", []):
            draw_text(self.surface, f"  ◆ {b}", rect.left + 12, y,
                      self.fonts.tiny, C["dim"])
            y += 17

        if sel:
            ck = pygame.Rect(rect.right - 26, rect.top + 8, 22, 22)
            pygame.draw.circle(self.surface, col, ck.center, 11)
            draw_text(self.surface, "✓", ck.centerx - 5, ck.top + 3,
                      self.fonts.small, C["black"])
