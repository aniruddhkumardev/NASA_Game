"""
Main Menu Screen
"""
import pygame
import math
from src.screens.base import BaseScreen
from src.constants import C, WIDTH, HEIGHT
from src.ui import Button, StarField, draw_text, rounded_rect, draw_glow


class MainMenuScreen(BaseScreen):
    def __init__(self, gs, surf):
        super().__init__(gs, surf)
        self.stars = StarField(250)
        self.t = 0
        self.particles = []

        cx = WIDTH // 2
        self.btn_play   = Button((cx - 140, 360, 280, 55), "START MISSION",
                                 C["btn_green"], C["btn_green_h"], self.fonts.heading,
                                 icon="🚀")
        self.btn_howto  = Button((cx - 140, 430, 280, 50), "HOW TO PLAY",
                                 C["btn_normal"], C["btn_hover"], self.fonts.body,
                                 icon="📖")
        self.btn_scores = Button((cx - 140, 495, 280, 50), "HIGH SCORES",
                                 C["btn_normal"], C["btn_hover"], self.fonts.body,
                                 icon="🏆")
        self.btn_quit   = Button((cx - 140, 560, 280, 50), "QUIT",
                                 C["btn_red"], C["btn_red_h"], self.fonts.body,
                                 icon="✕")
        self.showing_howto  = False
        self.showing_scores = False
        self.next_screen = None

    def handle_event(self, event):
        if self.showing_howto or self.showing_scores:
            if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                self.showing_howto = False
                self.showing_scores = False
            if event.type == pygame.MOUSEBUTTONDOWN:
                self.showing_howto = False
                self.showing_scores = False
            return

        if self.btn_play.handle_event(event):
            self.next_screen = "player_setup"
        if self.btn_howto.handle_event(event):
            self.showing_howto = True
        if self.btn_scores.handle_event(event):
            self.showing_scores = True
        if self.btn_quit.handle_event(event):
            pygame.event.post(pygame.event.Event(pygame.QUIT))

    def update(self, dt):
        self.t += dt
        # spawn particles occasionally
        import random
        if random.random() < 0.06:
            self.particles.append({
                "x": random.randint(0, WIDTH),
                "y": HEIGHT + 5,
                "vx": random.uniform(-0.3, 0.3),
                "vy": random.uniform(-1.5, -0.5),
                "life": 1.0,
                "size": random.randint(1, 3),
                "col": random.choice([C["cyan"], C["blue"], C["magenta"], C["yellow"]]),
            })
        new_p = []
        for p in self.particles:
            p["x"] += p["vx"]
            p["y"] += p["vy"]
            p["life"] -= 0.005
            if p["life"] > 0:
                new_p.append(p)
        self.particles = new_p

    def draw(self):
        self.surface.fill(C["bg_dark"])
        self.stars.draw(self.surface)

        # particles
        for p in self.particles:
            alpha = int(p["life"] * 180)
            col = (*p["col"][:3], alpha)
            s = pygame.Surface((p["size"]*2, p["size"]*2), pygame.SRCALPHA)
            pygame.draw.circle(s, col, (p["size"], p["size"]), p["size"])
            self.surface.blit(s, (int(p["x"]), int(p["y"])),
                              special_flags=pygame.BLEND_ALPHA_SDL2)

        cx = WIDTH // 2
        t  = self.t

        # planet in background
        planet_y = 220
        pygame.draw.circle(self.surface, (30, 60, 120), (cx, planet_y), 90)
        pygame.draw.circle(self.surface, (40, 80, 160), (cx, planet_y), 88)
        # rings
        for r in range(115, 145, 6):
            alpha_val = 120 - (r - 115) * 4
            ring_surf = pygame.Surface((r*2, 30), pygame.SRCALPHA)
            pygame.draw.ellipse(ring_surf, (180, 200, 255, alpha_val), (0, 5, r*2, 20), 3)
            self.surface.blit(ring_surf, (cx - r, planet_y - 15),
                              special_flags=pygame.BLEND_ALPHA_SDL2)
        # atmosphere glow
        draw_glow(self.surface, cx, planet_y, 130, C["blue"], 60)

        # orbiting spacecraft
        orb_r = 160
        orb_x = cx + int(orb_r * math.cos(t * 0.6))
        orb_y = planet_y + int(40 * math.sin(t * 0.6))
        draw_glow(self.surface, orb_x, orb_y, 20, C["cyan"], 100)
        pygame.draw.circle(self.surface, C["cyan"], (orb_x, orb_y), 5)
        pygame.draw.circle(self.surface, C["white"], (orb_x, orb_y), 3)

        # title
        title_y = 290
        draw_text(self.surface, "SPACE MISSION", cx, title_y,
                  self.fonts.title_xl, C["cyan"], center=True)
        draw_text(self.surface, "DESIGN GAME", cx, title_y + 56,
                  self.fonts.title_xl, C["white"], center=True)
        draw_text(self.surface, "Design · Build · Launch · Discover",
                  cx, title_y + 108, self.fonts.body, C["dim"], center=True)

        # buttons
        if not self.showing_howto and not self.showing_scores:
            self.btn_play.draw(self.surface)
            self.btn_howto.draw(self.surface)
            self.btn_scores.draw(self.surface)
            self.btn_quit.draw(self.surface)

        # version
        draw_text(self.surface, "v1.0  |  Up to 4 players  |  Press START to begin",
                  cx, HEIGHT - 30, self.fonts.tiny, C["dim"], center=True)

        if self.showing_howto:
            self._draw_howto()
        elif self.showing_scores:
            self._draw_scores()

    def _draw_howto(self):
        overlay = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 180))
        self.surface.blit(overlay, (0, 0))

        panel = pygame.Rect(100, 80, WIDTH - 200, HEIGHT - 160)
        rounded_rect(self.surface, panel, C["bg_panel"], 16, border=2, border_color=C["border_hl"])

        draw_text(self.surface, "HOW TO PLAY", panel.centerx, panel.top + 20,
                  self.fonts.title, C["cyan"], center=True)

        lines = [
            ("1. Player Setup",   "Choose 1–4 players and assign mission roles."),
            ("2. Scenario",       "Pick a mission target: Moon, Mars, Asteroid, Jupiter."),
            ("3. Spacecraft Bus", "Choose your satellite platform (size & capability)."),
            ("4. Power System",   "Solar panels work near the Sun. Use RTG for deep space."),
            ("5. Instruments",    "Add science instruments — balance science vs mass & power."),
            ("6. Orbit & Launch", "Pick an orbit and a rocket that can lift your payload."),
            ("7. Review",         "Check for errors — over budget, overweight, power deficit."),
            ("8. Simulate!",      "Watch your mission unfold with random events and scoring."),
        ]
        y = panel.top + 80
        for head, body in lines:
            draw_text(self.surface, head, panel.left + 30, y, self.fonts.body, C["yellow"])
            draw_text(self.surface, body, panel.left + 240, y, self.fonts.body, C["grey"])
            y += 36

        draw_text(self.surface, "Click anywhere or press ESC to close",
                  panel.centerx, panel.bottom - 36, self.fonts.small, C["dim"], center=True)

    def _draw_scores(self):
        overlay = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 180))
        self.surface.blit(overlay, (0, 0))

        panel = pygame.Rect(200, 120, WIDTH - 400, HEIGHT - 240)
        rounded_rect(self.surface, panel, C["bg_panel"], 16, border=2, border_color=C["border_hl"])

        draw_text(self.surface, "🏆  HIGH SCORES", panel.centerx, panel.top + 20,
                  self.fonts.title, C["gold"], center=True)

        scores = self.gs.high_scores
        if not scores:
            draw_text(self.surface, "No missions completed yet. Launch your first!",
                      panel.centerx, panel.centery, self.fonts.body, C["dim"], center=True)
        else:
            medals = ["🥇", "🥈", "🥉"]
            for i, (name, score, scen, success) in enumerate(scores[:8]):
                y = panel.top + 75 + i * 40
                medal = medals[i] if i < 3 else f"#{i+1}"
                col   = C["gold"] if i == 0 else C["grey"] if i == 1 else C["orange"] if i == 2 else C["white"]
                draw_text(self.surface, medal,          panel.left + 20, y, self.fonts.body, col)
                draw_text(self.surface, name,           panel.left + 60, y, self.fonts.body, C["white"])
                draw_text(self.surface, scen,           panel.left + 280, y, self.fonts.body, C["dim"])
                status_col = C["green"] if success else C["red"]
                draw_text(self.surface, "✓" if success else "✗",
                          panel.left + 440, y, self.fonts.body, status_col)
                draw_text(self.surface, f"{score:,} pts",
                          panel.right - 30, y, self.fonts.body, col, right=True)

        draw_text(self.surface, "Click anywhere to close",
                  panel.centerx, panel.bottom - 36, self.fonts.small, C["dim"], center=True)
