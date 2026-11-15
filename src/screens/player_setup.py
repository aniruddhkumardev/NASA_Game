"""
Player Setup Screen — choose number of players, names, roles, difficulty
"""
import pygame
from src.screens.base import BaseScreen
from src.constants import C, WIDTH, HEIGHT, ROLE_NAMES, ROLE_COLORS, DIFFICULTIES
from src.ui import Button, StarField, draw_text, rounded_rect, draw_multiline


class PlayerSetupScreen(BaseScreen):
    def __init__(self, gs, surf):
        super().__init__(gs, surf)
        self.stars = StarField(200)
        self.num_players = 1
        self.names  = ["Commander", "Engineer", "Scientist", "Comms Officer"]
        self.roles  = list(ROLE_NAMES)
        self.difficulty = "Engineer"
        self.editing_idx  = None     # which name is being typed
        self.typing_buf   = ""

        # num player buttons
        self.btn_np = [
            Button((WIDTH//2 - 200 + i*100, 185, 86, 42), str(i+1),
                   C["btn_normal"], C["btn_hover"], self.fonts.heading)
            for i in range(4)
        ]

        # difficulty buttons
        diffs = list(DIFFICULTIES.keys())
        self.btn_diff = [
            Button((WIDTH//2 - 260 + i*130, 295, 116, 40),
                   DIFFICULTIES[d]["label"],
                   C["bg_card"], C["bg_card_hl"], self.fonts.body)
            for i, d in enumerate(diffs)
        ]
        self.diff_keys = diffs

        self.btn_start = Button((WIDTH//2 - 110, HEIGHT - 90, 220, 52),
                                "BEGIN MISSION", C["btn_green"], C["btn_green_h"],
                                self.fonts.heading, icon="🚀")
        self.btn_back  = Button((40, HEIGHT - 90, 120, 52),
                                "BACK", C["btn_normal"], C["btn_hover"], self.fonts.body)

        self.next_screen = None

    def handle_event(self, event):
        # num players
        for i, btn in enumerate(self.btn_np):
            if btn.handle_event(event):
                self.num_players = i + 1

        # difficulty
        for i, btn in enumerate(self.btn_diff):
            if btn.handle_event(event):
                self.difficulty = self.diff_keys[i]

        # name editing
        if event.type == pygame.MOUSEBUTTONDOWN:
            clicked_name = False
            for i in range(self.num_players):
                name_rect = pygame.Rect(WIDTH//2 - 300, 380 + i*90, 320, 38)
                if name_rect.collidepoint(event.pos):
                    self.editing_idx = i
                    self.typing_buf  = self.names[i]
                    clicked_name = True
            if not clicked_name:
                self.editing_idx = None

        if event.type == pygame.KEYDOWN and self.editing_idx is not None:
            if event.key == pygame.K_RETURN:
                if self.typing_buf.strip():
                    self.names[self.editing_idx] = self.typing_buf.strip()
                self.editing_idx = None
            elif event.key == pygame.K_ESCAPE:
                self.editing_idx = None
            elif event.key == pygame.K_BACKSPACE:
                self.typing_buf = self.typing_buf[:-1]
            else:
                if len(self.typing_buf) < 18 and event.unicode.isprintable():
                    self.typing_buf += event.unicode

        if self.btn_start.handle_event(event):
            self._commit()
            self.next_screen = "scenario"
        if self.btn_back.handle_event(event):
            self.next_screen = "main_menu"

    def _commit(self):
        self.gs.players.clear()
        for i in range(self.num_players):
            self.gs.add_player(self.names[i], self.roles[i])
        self.gs.mission.difficulty = self.difficulty
        self.gs.num_players = self.num_players

    def draw(self):
        self.surface.fill(C["bg_dark"])
        self.stars.draw(self.surface)
        self.draw_header("Space Mission Design", "Mission Control Setup", "Phase 1 / 9")

        cx = WIDTH // 2

        # ── Number of players ─────────────────────────────────────────
        draw_text(self.surface, "Number of Players", cx, 152,
                  self.fonts.heading, C["white"], center=True)

        for i, btn in enumerate(self.btn_np):
            btn.color = C["btn_active"] if (i+1) == self.num_players else C["btn_normal"]
            btn.hover_color = C["btn_hover"]
            btn.draw(self.surface)
            col_ring = ROLE_COLORS[i]
            if (i+1) == self.num_players:
                pygame.draw.rect(self.surface, col_ring,
                                 btn.rect.inflate(4,4), 2, border_radius=8)

        # ── Difficulty ────────────────────────────────────────────────
        draw_text(self.surface, "Difficulty", cx, 262,
                  self.fonts.heading, C["white"], center=True)

        for i, (btn, key) in enumerate(zip(self.btn_diff, self.diff_keys)):
            d = DIFFICULTIES[key]
            is_sel = key == self.difficulty
            btn.color = d["color"] if is_sel else C["bg_card"]
            btn.text_color = C["black"] if is_sel else C["grey"]
            btn.draw(self.surface)
            if is_sel:
                pygame.draw.rect(self.surface, d["color"],
                                 btn.rect.inflate(4,4), 2, border_radius=8)

        # Difficulty hint
        d_info = DIFFICULTIES[self.difficulty]
        hint = {
            "Cadet":    "Budget ×1.3 — 2 random events. Great for beginners.",
            "Engineer": "Standard budget — 4 random events. Recommended.",
            "Director": "Budget ×0.8 — 6 events. Tight margins.",
            "Legend":   "Budget ×0.6 — 8 events. Only experts survive.",
        }[self.difficulty]
        draw_text(self.surface, hint, cx, 345, self.fonts.small, C["dim"], center=True)

        # ── Player slots ──────────────────────────────────────────────
        draw_text(self.surface, "Player Names & Roles", cx, 368,
                  self.fonts.heading, C["white"], center=True)

        for i in range(4):
            slot_y = 398 + i * 82
            active  = i < self.num_players
            alpha   = 255 if active else 60
            col     = ROLE_COLORS[i]

            # card background
            card = pygame.Rect(cx - 310, slot_y, 620, 70)
            bg_col = (*C["bg_card"][:3],) if active else (*C["bg_header"][:3],)
            rounded_rect(self.surface, card, bg_col, 10,
                         border=2, border_color=col if active else C["border"])

            # role badge
            badge = pygame.Rect(card.left + 8, card.top + 8, 160, 54)
            rounded_rect(self.surface, badge, (*col, 40), 8)
            draw_text(self.surface, f"P{i+1}", badge.left + 10, badge.top + 5,
                      self.fonts.heading, col if active else C["dim"])
            draw_text(self.surface, ROLE_NAMES[i], badge.left + 45, badge.top + 8,
                      self.fonts.small, col if active else C["dim"])

            # name input field
            inp_rect = pygame.Rect(card.left + 178, card.top + 16, 280, 36)
            inp_bg = C["bg_card_hl"] if (self.editing_idx == i and active) else C["bg_panel"]
            inp_border = col if (self.editing_idx == i and active) else C["border"]
            rounded_rect(self.surface, inp_rect, inp_bg, 6, border=2, border_color=inp_border)

            display_name = (self.typing_buf + "|") if self.editing_idx == i else self.names[i]
            name_col = C["white"] if active else C["dim"]
            draw_text(self.surface, display_name,
                      inp_rect.left + 10, inp_rect.top + 8,
                      self.fonts.body, name_col)

            if active and self.editing_idx != i:
                draw_text(self.surface, "click to edit",
                          inp_rect.right + 10, inp_rect.top + 10,
                          self.fonts.tiny, C["dim"])

        self.btn_start.draw(self.surface)
        self.btn_back.draw(self.surface)
