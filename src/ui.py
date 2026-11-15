"""
Reusable UI widgets — buttons, cards, resource bars, panels
"""
import pygame
import math
from src.constants import C, WIDTH, HEIGHT


def draw_text(surf, text, x, y, font, color=None, center=False, right=False):
    color = color or C["white"]
    rendered = font.render(str(text), True, color)
    rect = rendered.get_rect()
    if center:
        rect.centerx = x
        rect.top = y
    elif right:
        rect.right = x
        rect.top = y
    else:
        rect.left = x
        rect.top = y
    surf.blit(rendered, rect)
    return rect


def draw_multiline(surf, text, x, y, font, color=None, line_height=None, max_width=None):
    color = color or C["white"]
    lh = line_height or font.get_height() + 4
    words = text.split()
    lines = []
    cur = []
    for w in words:
        test = " ".join(cur + [w])
        if max_width and font.size(test)[0] > max_width:
            lines.append(" ".join(cur))
            cur = [w]
        else:
            cur.append(w)
    if cur:
        lines.append(" ".join(cur))
    for i, line in enumerate(lines):
        draw_text(surf, line, x, y + i * lh, font, color)
    return y + len(lines) * lh


def rounded_rect(surf, rect, color, radius=10, border=0, border_color=None):
    pygame.draw.rect(surf, color, rect, border_radius=radius)
    if border:
        pygame.draw.rect(surf, border_color or C["border_hl"], rect, border, border_radius=radius)


def draw_glow(surf, cx, cy, radius, color, alpha=80):
    glow = pygame.Surface((radius*2, radius*2), pygame.SRCALPHA)
    for r in range(radius, 0, -4):
        a = int(alpha * (1 - r/radius))
        pygame.draw.circle(glow, (*color[:3], a), (radius, radius), r)
    surf.blit(glow, (cx - radius, cy - radius), special_flags=pygame.BLEND_ALPHA_SDL2)


class Button:
    def __init__(self, rect, text, color=None, hover_color=None,
                 font=None, text_color=None, radius=10,
                 icon=None, disabled=False, tooltip=None):
        self.rect        = pygame.Rect(rect)
        self.text        = text
        self.color       = color or C["btn_normal"]
        self.hover_color = hover_color or C["btn_hover"]
        self.font        = font
        self.text_color  = text_color or C["white"]
        self.radius      = radius
        self.icon        = icon
        self.disabled    = disabled
        self.tooltip     = tooltip
        self._hovered    = False
        self._pressed    = False

    def handle_event(self, event):
        if self.disabled:
            return False
        if event.type == pygame.MOUSEMOTION:
            self._hovered = self.rect.collidepoint(event.pos)
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.rect.collidepoint(event.pos):
                self._pressed = True
                return True
        if event.type == pygame.MOUSEBUTTONUP:
            self._pressed = False
        return False

    def draw(self, surf):
        if self.disabled:
            col = C["btn_disabled"]
        elif self._hovered:
            col = self.hover_color
        else:
            col = self.color

        rounded_rect(surf, self.rect, col, self.radius)
        if self._hovered and not self.disabled:
            rounded_rect(surf, self.rect, (0,0,0,0), self.radius,
                         border=2, border_color=C["border_hl"])

        if self.font:
            lbl = (self.icon + "  " + self.text) if self.icon else self.text
            draw_text(surf, lbl, self.rect.centerx, self.rect.centery - self.font.get_height()//2,
                      self.font, self.text_color if not self.disabled else C["dim"], center=True)

        if self._hovered and self.tooltip and self.font:
            tip_surf = self.font.render(self.tooltip, True, C["white"])
            tip_rect = tip_surf.get_rect(bottomleft=(self.rect.left, self.rect.top - 4))
            bg = tip_rect.inflate(12, 6)
            rounded_rect(surf, bg, C["bg_card"], 6, border=1, border_color=C["border"])
            surf.blit(tip_surf, tip_rect)


class SelectCard:
    """A selectable card for choosing items (spacecraft, instruments, etc.)"""
    def __init__(self, rect, data, font_title, font_body,
                 selected=False, multi=False):
        self.rect       = pygame.Rect(rect)
        self.data       = data
        self.font_title = font_title
        self.font_body  = font_body
        self.selected   = selected
        self.multi      = multi     # multi-select vs single-select
        self._hovered   = False

    def handle_event(self, event):
        if event.type == pygame.MOUSEMOTION:
            self._hovered = self.rect.collidepoint(event.pos)
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            if self.rect.collidepoint(event.pos):
                if self.multi:
                    self.selected = not self.selected
                else:
                    self.selected = True
                return True
        return False

    def draw(self, surf):
        color = C["bg_card"]
        border_col = C["border"]
        if self.selected:
            color = C["bg_card_hl"]
            border_col = self.data.get("color", C["border_hl"])
        elif self._hovered:
            color = (25, 38, 85)
            border_col = C["border_hl"]

        rounded_rect(surf, self.rect, color, 12, border=2, border_color=border_col)

        if self.selected:
            # glow effect
            glow_col = self.data.get("color", C["border_hl"])
            for i in range(3):
                r2 = self.rect.inflate(i*2, i*2)
                pygame.draw.rect(surf, (*glow_col, 30 - i*8), r2, 1, border_radius=14)

        # icon
        icon = self.data.get("icon", "?")
        ix, iy = self.rect.x + 14, self.rect.y + 12
        col = self.data.get("color", C["white"])
        draw_text(surf, icon, ix, iy, self.font_title, col)

        # name
        draw_text(surf, self.data["name"],
                  ix + 40, iy, self.font_title, C["white"])

        # desc
        draw_multiline(surf, self.data.get("desc", ""),
                       self.rect.x + 14, iy + 30,
                       self.font_body, C["grey"],
                       max_width=self.rect.width - 28)

        # stats row at bottom
        stats = []
        if "mass" in self.data:   stats.append(f"⚖ {self.data['mass']} kg")
        if "power" in self.data:  stats.append(f"⚡ {self.data['power']} W")
        if "cost" in self.data:   stats.append(f"💰 ${self.data['cost']}M")
        if "science" in self.data: stats.append(f"🔬 +{self.data['science']}")
        if "power_gen" in self.data: stats.append(f"⚡ +{self.data['power_gen']} W")
        if "capacity" in self.data: stats.append(f"⚖ ≤{self.data['capacity']} kg")
        if "reliability" in self.data: stats.append(f"✓ {int(self.data['reliability']*100)}%")

        stat_y = self.rect.bottom - self.font_body.get_height() - 10
        sx = self.rect.x + 10
        for s in stats[:5]:
            tw = self.font_body.size(s)[0]
            rounded_rect(surf, pygame.Rect(sx-4, stat_y-2, tw+8, self.font_body.get_height()+4),
                         C["bg_header"], 4)
            draw_text(surf, s, sx, stat_y, self.font_body, C["cyan"])
            sx += tw + 16

        # selected checkmark
        if self.selected:
            ck_rect = pygame.Rect(self.rect.right - 28, self.rect.top + 8, 20, 20)
            pygame.draw.circle(surf, self.data.get("color", C["green"]),
                               ck_rect.center, 10)
            draw_text(surf, "✓", ck_rect.centerx - 5, ck_rect.top + 1,
                      self.font_body, C["black"])


class ResourceBar:
    def __init__(self, x, y, w, h, label, value, max_val,
                 bar_color=None, warn_at=0.8, crit_at=0.95, inverted=False):
        self.rect      = pygame.Rect(x, y, w, h)
        self.label     = label
        self.value     = value
        self.max_val   = max_val
        self.bar_color = bar_color or C["bar_budget"]
        self.warn_at   = warn_at
        self.crit_at   = crit_at
        self.inverted  = inverted   # for power: positive = good

    def draw(self, surf, font):
        frac = max(0, min(1, abs(self.value) / max(abs(self.max_val), 0.01)))
        # color based on usage
        if self.inverted:
            col = C["green"] if self.value >= 0 else C["red"]
        else:
            if frac >= self.crit_at:
                col = C["red"]
            elif frac >= self.warn_at:
                col = C["orange"]
            else:
                col = self.bar_color

        # background
        pygame.draw.rect(surf, C["bar_bg"], self.rect, border_radius=6)
        # fill
        fill_w = int(self.rect.width * frac)
        if fill_w > 0:
            fill_rect = pygame.Rect(self.rect.x, self.rect.y, fill_w, self.rect.height)
            pygame.draw.rect(surf, col, fill_rect, border_radius=6)
        # border
        pygame.draw.rect(surf, C["border"], self.rect, 1, border_radius=6)

        # label
        draw_text(surf, self.label,
                  self.rect.x, self.rect.y - font.get_height() - 2,
                  font, C["grey"])
        # value
        if self.inverted:
            val_str = f"{'+' if self.value >= 0 else ''}{self.value:.0f} W"
        else:
            val_str = f"{self.value:.0f} / {self.max_val}"
        draw_text(surf, val_str, self.rect.right, self.rect.y - font.get_height() - 2,
                  font, col, right=True)


class ScrollPanel:
    """Scrollable text log panel"""
    def __init__(self, rect, font, bg_color=None):
        self.rect      = pygame.Rect(rect)
        self.font      = font
        self.bg_color  = bg_color or C["bg_panel"]
        self.lines     = []
        self.scroll_y  = 0
        self.line_h    = font.get_height() + 3
        self._surf     = None

    def set_lines(self, lines):
        self.lines   = lines
        self.scroll_y = max(0, len(lines) * self.line_h - self.rect.height + 20)

    def handle_event(self, event):
        if event.type == pygame.MOUSEWHEEL:
            if self.rect.collidepoint(pygame.mouse.get_pos()):
                self.scroll_y = max(0, self.scroll_y - event.y * self.line_h * 3)

    def draw(self, surf):
        # clip to rect
        old_clip = surf.get_clip()
        surf.set_clip(self.rect)

        pygame.draw.rect(surf, self.bg_color, self.rect, border_radius=8)

        y = self.rect.y + 8 - self.scroll_y
        for line in self.lines:
            col = C["green"] if "SUCCESS" in line else \
                  C["red"]   if "FAIL" in line else \
                  C["gold"]  if "Score" in line else \
                  C["cyan"]  if line.startswith("T+") else \
                  C["yellow"] if "Day" in line else C["grey"]
            draw_text(surf, line, self.rect.x + 10, y, self.font, col)
            y += self.line_h

        pygame.draw.rect(surf, C["border"], self.rect, 1, border_radius=8)
        surf.set_clip(old_clip)


class StarField:
    """Animated star background."""
    def __init__(self, n=220, w=WIDTH, h=HEIGHT):
        self.stars = [
            (
                int(pygame.math.Vector2(1,0).rotate(i * 360/n).x * (w//2) + w//2),
                int(pygame.math.Vector2(1,0).rotate(i * 360/n).y * (h//2) + h//2),
                random.randint(1, 3),
                random.randint(80, 220),
            )
            for i in range(n)
        ]
        import random as r
        self.stars = [
            (r.randint(0, w), r.randint(0, h),
             r.randint(1, 3), r.randint(60, 220))
            for _ in range(n)
        ]
        self.t = 0

    def draw(self, surf):
        self.t += 1
        for (x, y, size, base_alpha) in self.stars:
            twinkle = base_alpha + int(40 * math.sin(self.t * 0.04 + x))
            twinkle = max(40, min(255, twinkle))
            col = (twinkle, twinkle, twinkle)
            pygame.draw.circle(surf, col, (x, y), size)


import random  # for StarField init fallback
