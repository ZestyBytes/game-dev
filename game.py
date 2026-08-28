#!/usr/bin/env python3
"""
ASCII Candy Crush - a simple terminal match-3 game, built for easy play.

HOW TO PLAY
  - Pick a player (or make a new one with a name and an animal avatar).
  - Use the ARROW KEYS to move the cursor around the board.
  - Press SPACE (or ENTER) on a candy to pick it up.
  - Move to a candy next to it and press SPACE again to swap them.
  - If 3 or more matching candies line up, they flash and pop -
    score points!
  - Line up 4 in a row to make a POWER CANDY that clears a whole
    row or column. Line up 5 to make a COLOR BOMB that clears every
    candy of that color on the board!
  - Reach the target score before you run out of moves to win.
  - Press Q to quit any time.

Every candy is hand-drawn from solid blocks (not a font symbol), so every
shape is guaranteed to look the same size and sit the same way in its box:
  circle    square    triangle    diamond    cross

A power candy glows instead of showing an extra symbol:
  bold             = clears the whole ROW when matched
  bold + underline = clears the whole COLUMN when matched
  bold + blinking  = COLOR BOMB - clears every candy of that color

High scores (with your avatar) are saved between games.
"""

import curses
import json
import random
from datetime import date
from pathlib import Path

BOARD_SIZE = 8
TARGET_SCORE = 400
START_MOVES = 20
FLASH_BLINKS = 2
FLASH_DELAY_MS = 110
SETTLE_DELAY_MS = 130

# Each candy is drawn as a hand-built 5-wide x 3-tall sprite out of plain
# ASCII characters. Block-drawing characters (█ ▄ ▀) turned out to render
# double-width in some terminal/font combinations (even though box-drawing
# lines like ┌─│ render single-width) - plain ASCII is unambiguously
# single-width everywhere, so it's the only safe choice for a fixed grid.
CANDY_SPRITES = {
    "circle": [" ### ", "#####", " ### "],
    "square": ["#####", "#####", "#####"],
    "triangle": ["  #  ", " ### ", "#####"],
    "diamond": ["  #  ", " ### ", "  #  "],
    "cross": ["  #  ", "#####", "  #  "],
}
CANDY_TYPES = list(CANDY_SPRITES.keys())

COLOR_FOR_SHAPE = {
    "circle": curses.COLOR_RED,
    "square": curses.COLOR_GREEN,
    "triangle": curses.COLOR_YELLOW,
    "diamond": curses.COLOR_BLUE,
    "cross": curses.COLOR_MAGENTA,
}

DATA_DIR = Path.home() / ".local" / "share" / "ascii-candy-crush"
SCORES_FILE = DATA_DIR / "scores.json"
PROFILES_FILE = DATA_DIR / "profiles.json"
MAX_LEADERBOARD = 10

AVATARS = ["\U0001F431", "\U0001F436", "\U0001F98A", "\U0001F430", "\U0001F43C", "\U0001F438", "\U0001F981", "\U0001F435"]


class Candy:
    """A single candy on the board. `special` is None, 'row', 'col', or 'color'."""

    __slots__ = ("symbol", "special")

    def __init__(self, symbol, special=None):
        self.symbol = symbol
        self.special = special


def random_candy():
    return Candy(random.choice(CANDY_TYPES))


def find_match_runs(board):
    """Return a list of {'cells': [(r, c), ...], 'dir': 'row'|'col'} for every
    run of 3+ matching candies, horizontal and vertical."""
    runs = []

    for r in range(BOARD_SIZE):
        run_start = 0
        for c in range(1, BOARD_SIZE + 1):
            same = (
                c < BOARD_SIZE
                and board[r][c] is not None
                and board[r][run_start] is not None
                and board[r][c].symbol == board[r][run_start].symbol
            )
            if not same:
                if c - run_start >= 3:
                    runs.append({"cells": [(r, cc) for cc in range(run_start, c)], "dir": "row"})
                run_start = c

    for c in range(BOARD_SIZE):
        run_start = 0
        for r in range(1, BOARD_SIZE + 1):
            same = (
                r < BOARD_SIZE
                and board[r][c] is not None
                and board[run_start][c] is not None
                and board[r][c].symbol == board[run_start][c].symbol
            )
            if not same:
                if r - run_start >= 3:
                    runs.append({"cells": [(rr, c) for rr in range(run_start, r)], "dir": "col"})
                run_start = r

    return runs


def create_board():
    board = [[random_candy() for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
    while find_match_runs(board):
        for run in find_match_runs(board):
            for r, c in run["cells"]:
                board[r][c] = random_candy()
    return board


def is_adjacent(pos1, pos2):
    r1, c1 = pos1
    r2, c2 = pos2
    return abs(r1 - r2) + abs(c1 - c2) == 1


def swap_cells(board, pos1, pos2):
    r1, c1 = pos1
    r2, c2 = pos2
    board[r1][c1], board[r2][c2] = board[r2][c2], board[r1][c1]


def resolve_board_steps(board, score, swapped_pos=None):
    """Generator that resolves matches/cascades one animation beat at a time.

    Yields:
      ('flash', {positions}, score)  - these candies are about to pop (unclear yet)
      ('popped', None, score)        - they've been cleared (holes), score updated
      ('refilled', None, score)      - gravity applied, new candies dropped in
      ('done', matched_any, score)   - resolution finished (final event, always last)
    """
    matched_any = False

    while True:
        runs = find_match_runs(board)
        if not runs:
            break
        matched_any = True

        clear_set = set()
        new_specials = {}

        for run in runs:
            cells = run["cells"]
            length = len(cells)
            if length >= 4:
                anchor = swapped_pos if swapped_pos in cells else cells[length // 2]
                new_specials[anchor] = "color" if length >= 5 else run["dir"]
                for pos in cells:
                    if pos != anchor:
                        clear_set.add(pos)
            else:
                clear_set.update(cells)

        # Trigger any power candies caught in the blast (can cascade further).
        frontier = set(clear_set)
        seen = set()
        while frontier:
            next_frontier = set()
            for pos in frontier:
                if pos in seen:
                    continue
                seen.add(pos)
                r, c = pos
                cell = board[r][c]
                if cell is None:
                    continue
                if cell.special == "row":
                    for cc in range(BOARD_SIZE):
                        p = (r, cc)
                        if p not in clear_set:
                            clear_set.add(p)
                            next_frontier.add(p)
                elif cell.special == "col":
                    for rr in range(BOARD_SIZE):
                        p = (rr, c)
                        if p not in clear_set:
                            clear_set.add(p)
                            next_frontier.add(p)
                elif cell.special == "color":
                    symbol = cell.symbol
                    for rr in range(BOARD_SIZE):
                        for cc in range(BOARD_SIZE):
                            p = (rr, cc)
                            if p not in clear_set and board[rr][cc] is not None and board[rr][cc].symbol == symbol:
                                clear_set.add(p)
                                next_frontier.add(p)
            frontier = next_frontier

        # Anchors becoming new power candies must survive this pass.
        clear_set -= set(new_specials.keys())

        yield ("flash", set(clear_set), score)

        score += len(clear_set) * 10 + len(new_specials) * 50

        for r, c in clear_set:
            board[r][c] = None

        for (r, c), special_type in new_specials.items():
            if board[r][c] is not None:
                board[r][c].special = special_type

        yield ("popped", None, score)

        for c in range(BOARD_SIZE):
            column = [board[r][c] for r in range(BOARD_SIZE) if board[r][c] is not None]
            missing = BOARD_SIZE - len(column)
            new_column = [random_candy() for _ in range(missing)] + column
            for r in range(BOARD_SIZE):
                board[r][c] = new_column[r]

        yield ("refilled", None, score)

        swapped_pos = None  # only the first pass favors the swapped position

    yield ("done", matched_any, score)


def resolve_board(board, score, swapped_pos=None):
    """Non-animated version: drains resolve_board_steps and returns the final
    (score, matched_any). Handy for testing or a no-animation fallback."""
    matched_any = False
    for kind, payload, score in resolve_board_steps(board, score, swapped_pos):
        if kind == "done":
            matched_any = payload
    return score, matched_any


# ---------------------------------------------------------------------------
# Persistence: player profiles and high scores
# ---------------------------------------------------------------------------


def _load_json_list(path):
    try:
        with open(path) as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    return []


def _save_json_list(path, data):
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
    except OSError:
        pass  # not worth crashing the game over a save failure


def load_profiles():
    return _load_json_list(PROFILES_FILE)


def save_profiles(profiles):
    _save_json_list(PROFILES_FILE, profiles)


def load_scores():
    return _load_json_list(SCORES_FILE)


def add_score(name, avatar, score):
    scores = load_scores()
    scores.append({"name": name, "avatar": avatar, "score": score, "date": date.today().isoformat()})
    scores = sorted(scores, key=lambda entry: entry.get("score", 0), reverse=True)[:MAX_LEADERBOARD]
    _save_json_list(SCORES_FILE, scores)
    return scores


# ---------------------------------------------------------------------------
# Display (curses)
# ---------------------------------------------------------------------------

TOP_MARGIN = 3
LEFT_MARGIN = 2
CELL_WIDTH = 5  # sprite width (see CANDY_SPRITES)
CELL_HEIGHT = 3  # sprite height (see CANDY_SPRITES)

GRID_WIDTH = 1 + BOARD_SIZE * (CELL_WIDTH + 1)
GRID_HEIGHT = 2 + BOARD_SIZE * CELL_HEIGHT  # top border + content rows + bottom border
NEEDED_COLS = LEFT_MARGIN + GRID_WIDTH + 2
NEEDED_LINES = TOP_MARGIN + GRID_HEIGHT + 6

# Extra color pairs (beyond one per candy shape) for fully-filled highlights.
CURSOR_PAIR = len(CANDY_TYPES) + 1
SELECTED_PAIR = len(CANDY_TYPES) + 2
FLASH_PAIR = len(CANDY_TYPES) + 3


def init_colors():
    curses.start_color()
    curses.use_default_colors()
    for i, shape in enumerate(CANDY_TYPES, start=1):
        curses.init_pair(i, COLOR_FOR_SHAPE[shape], -1)
    curses.init_pair(CURSOR_PAIR, curses.COLOR_BLACK, curses.COLOR_CYAN)
    curses.init_pair(SELECTED_PAIR, curses.COLOR_BLACK, curses.COLOR_YELLOW)
    curses.init_pair(FLASH_PAIR, curses.COLOR_BLACK, curses.COLOR_WHITE)


def color_pair_for(shape):
    return curses.color_pair(CANDY_TYPES.index(shape) + 1)


def special_attr(special):
    """Attribute combo that shows a power candy's type without changing its
    shape or size."""
    if special == "row":
        return curses.A_BOLD
    if special == "col":
        return curses.A_BOLD | curses.A_UNDERLINE
    if special == "color":
        return curses.A_BOLD | curses.A_BLINK
    return 0


def _h_line(left, mid, right):
    return left + mid.join(["─" * CELL_WIDTH] * BOARD_SIZE) + right


GRID_TOP_LINE = _h_line("┌", "┬", "┐")
GRID_BOTTOM_LINE = _h_line("└", "┴", "┘")
GRID_BLANK_ROW = "│" + "│".join([" " * CELL_WIDTH] * BOARD_SIZE) + "│"


def cell_x(c):
    return LEFT_MARGIN + 1 + c * (CELL_WIDTH + 1)


def cell_top_y(r):
    return TOP_MARGIN + 1 + r * CELL_HEIGHT


def draw(stdscr, board, cursor, selected, score, moves_left, message, pop_positions=None, pop_lit=True):
    pop_positions = pop_positions or set()

    stdscr.erase()
    stdscr.addstr(0, LEFT_MARGIN, "ASCII CANDY CRUSH", curses.A_BOLD)
    stdscr.addstr(
        1,
        LEFT_MARGIN,
        f"Score: {score:<5} Target: {TARGET_SCORE:<5} Moves left: {moves_left}",
    )

    stdscr.addstr(TOP_MARGIN, LEFT_MARGIN, GRID_TOP_LINE, curses.A_DIM)

    for r in range(BOARD_SIZE):
        top_y = cell_top_y(r)
        for sub in range(CELL_HEIGHT):
            stdscr.addstr(top_y + sub, LEFT_MARGIN, GRID_BLANK_ROW, curses.A_DIM)

        for c in range(BOARD_SIZE):
            pos = (r, c)
            cell = board[r][c]
            x = cell_x(c)

            if cell is None:
                continue  # leave the empty box blank

            sprite = CANDY_SPRITES[cell.symbol]

            if pos in pop_positions:
                attr = curses.color_pair(FLASH_PAIR) | curses.A_BOLD if pop_lit else color_pair_for(cell.symbol)
            elif pos == cursor:
                attr = curses.color_pair(CURSOR_PAIR)
            elif pos == selected:
                attr = curses.color_pair(SELECTED_PAIR)
            else:
                attr = color_pair_for(cell.symbol) | special_attr(cell.special)

            for sub in range(CELL_HEIGHT):
                stdscr.addstr(top_y + sub, x, sprite[sub], attr)

    grid_bottom = TOP_MARGIN + GRID_HEIGHT - 1
    stdscr.addstr(grid_bottom, LEFT_MARGIN, GRID_BOTTOM_LINE, curses.A_DIM)

    help_y = grid_bottom + 2
    stdscr.addstr(help_y, LEFT_MARGIN, message, curses.A_DIM)
    stdscr.addstr(
        help_y + 1,
        LEFT_MARGIN,
        "Arrows: move   SPACE/ENTER: pick up & swap   Q: quit",
    )
    stdscr.addstr(
        help_y + 2,
        LEFT_MARGIN,
        "Shapes: circle, square, triangle, diamond, cross - each its own color",
    )
    stdscr.addstr(
        help_y + 3,
        LEFT_MARGIN,
        "A glowing candy is a power candy - match it to see what it does!",
    )
    stdscr.refresh()


def play_resolution_animation(stdscr, board, cursor, selected, moves_left, score, swapped_pos):
    """Runs resolve_board_steps and animates each beat. Returns (score, matched_any)."""
    matched_any = False

    for kind, payload, new_score in resolve_board_steps(board, score, swapped_pos):
        if kind == "flash":
            for _ in range(FLASH_BLINKS):
                draw(stdscr, board, cursor, selected, new_score, moves_left, "Match!", payload, pop_lit=True)
                curses.napms(FLASH_DELAY_MS)
                draw(stdscr, board, cursor, selected, new_score, moves_left, "Match!", payload, pop_lit=False)
                curses.napms(FLASH_DELAY_MS)
            score = new_score
        elif kind in ("popped", "refilled"):
            draw(stdscr, board, cursor, selected, new_score, moves_left, "Match!")
            curses.napms(SETTLE_DELAY_MS)
            score = new_score
        elif kind == "done":
            matched_any = payload
            score = new_score

    return score, matched_any


# ---------------------------------------------------------------------------
# Player profiles (name + avatar)
# ---------------------------------------------------------------------------


def prompt_name(stdscr, y, x, max_len=12):
    """Simple text entry: type a name, Enter to confirm, Backspace to edit."""
    curses.curs_set(1)
    name = ""
    while True:
        stdscr.addstr(y, x, " " * (max_len + 1))
        stdscr.addstr(y, x, name)
        stdscr.move(y, x + len(name))
        stdscr.refresh()

        key = stdscr.getch()
        if key in (curses.KEY_ENTER, 10, 13) and name:
            break
        elif key in (curses.KEY_BACKSPACE, 127, 8):
            name = name[:-1]
        elif 32 <= key <= 126 and len(name) < max_len:
            name += chr(key)

    curses.curs_set(0)
    return name.strip() or "Player"


def create_new_profile(stdscr):
    stdscr.erase()
    stdscr.addstr(0, LEFT_MARGIN, "NEW PLAYER", curses.A_BOLD)
    prompt = "What's your name? "
    stdscr.addstr(2, LEFT_MARGIN, prompt)
    stdscr.refresh()
    name = prompt_name(stdscr, 2, LEFT_MARGIN + len(prompt))

    avatar_idx = 0
    while True:
        stdscr.erase()
        stdscr.addstr(0, LEFT_MARGIN, f"Pick an avatar, {name}!", curses.A_BOLD)
        stdscr.addstr(2, LEFT_MARGIN, f"Your avatar:  {AVATARS[avatar_idx]}")
        stdscr.addstr(4, LEFT_MARGIN, "LEFT / RIGHT: change    ENTER: confirm", curses.A_DIM)
        stdscr.refresh()
        key = stdscr.getch()
        if key == curses.KEY_LEFT:
            avatar_idx = (avatar_idx - 1) % len(AVATARS)
        elif key == curses.KEY_RIGHT:
            avatar_idx = (avatar_idx + 1) % len(AVATARS)
        elif key in (curses.KEY_ENTER, 10, 13, ord(" ")):
            break

    return {"name": name, "avatar": AVATARS[avatar_idx]}


def choose_profile_screen(stdscr):
    """'Who's playing?' screen. Returns the chosen {'name', 'avatar'} dict."""
    profiles = load_profiles()

    idx = 0
    while True:
        options = profiles + [{"name": "New Player", "avatar": "+"}]

        stdscr.erase()
        stdscr.addstr(0, LEFT_MARGIN, "ASCII CANDY CRUSH", curses.A_BOLD)
        stdscr.addstr(2, LEFT_MARGIN, "WHO'S PLAYING?", curses.A_BOLD | curses.A_UNDERLINE)
        for i, p in enumerate(options):
            attr = curses.A_REVERSE if i == idx else curses.A_NORMAL
            stdscr.addstr(4 + i, LEFT_MARGIN, f" {p['avatar']} {p['name']} ", attr)
        stdscr.addstr(4 + len(options) + 1, LEFT_MARGIN, "Arrows: choose   ENTER: select", curses.A_DIM)
        stdscr.refresh()

        key = stdscr.getch()
        if key == curses.KEY_UP:
            idx = (idx - 1) % len(options)
        elif key == curses.KEY_DOWN:
            idx = (idx + 1) % len(options)
        elif key in (curses.KEY_ENTER, 10, 13, ord(" ")):
            if idx == len(options) - 1:
                profile = create_new_profile(stdscr)
                profiles.append(profile)
                save_profiles(profiles)
                return profile
            return options[idx]


def show_leaderboard_screen(stdscr, scores):
    """Shows high scores. Returns the key the player pressed to continue."""
    stdscr.erase()
    stdscr.addstr(0, LEFT_MARGIN, "ASCII CANDY CRUSH", curses.A_BOLD)
    stdscr.addstr(2, LEFT_MARGIN, "HIGH SCORES", curses.A_BOLD | curses.A_UNDERLINE)

    if not scores:
        stdscr.addstr(4, LEFT_MARGIN, "No scores yet - be the first to play!")
        next_line = 6
    else:
        for i, entry in enumerate(scores[:MAX_LEADERBOARD]):
            stdscr.addstr(
                4 + i,
                LEFT_MARGIN,
                f"{i + 1:>2}. {entry.get('avatar', '')} {entry.get('name', 'Player'):<12} {entry.get('score', 0):>5}",
            )
        next_line = 4 + len(scores[:MAX_LEADERBOARD]) + 2

    stdscr.addstr(next_line, LEFT_MARGIN, "Press SPACE/ENTER to play  -  Q to quit", curses.A_BOLD)
    stdscr.refresh()
    return stdscr.getch()


def show_game_over_screen(stdscr, won, score, profile):
    stdscr.erase()
    title = "YOU WIN!" if won else "GAME OVER"
    stdscr.addstr(TOP_MARGIN, LEFT_MARGIN, title, curses.A_BOLD)
    stdscr.addstr(TOP_MARGIN + 1, LEFT_MARGIN, "Great job matching candies!" if won else "So close - try again!")
    stdscr.addstr(TOP_MARGIN + 3, LEFT_MARGIN, f"{profile['avatar']} {profile['name']} scored {score} points!")
    stdscr.addstr(TOP_MARGIN + 5, LEFT_MARGIN, "Press any key to continue...", curses.A_DIM)
    stdscr.refresh()
    stdscr.getch()
    add_score(profile["name"], profile["avatar"], score)


def play_round(stdscr, profile):
    """Plays one game from a fresh board until win/loss or quit.
    Returns True if the player quit outright (wants to exit the app)."""
    board = create_board()
    cursor = (0, 0)
    selected = None
    score = 0
    moves_left = START_MOVES
    message = "Good luck!"

    while True:
        draw(stdscr, board, cursor, selected, score, moves_left, message)

        if score >= TARGET_SCORE:
            show_game_over_screen(stdscr, won=True, score=score, profile=profile)
            return False
        if moves_left <= 0:
            show_game_over_screen(stdscr, won=False, score=score, profile=profile)
            return False

        key = stdscr.getch()
        r, c = cursor

        if key == curses.KEY_UP:
            cursor = (max(0, r - 1), c)
        elif key == curses.KEY_DOWN:
            cursor = (min(BOARD_SIZE - 1, r + 1), c)
        elif key == curses.KEY_LEFT:
            cursor = (r, max(0, c - 1))
        elif key == curses.KEY_RIGHT:
            cursor = (r, min(BOARD_SIZE - 1, c + 1))
        elif key in (ord(" "), curses.KEY_ENTER, 10, 13):
            if selected is None:
                selected = cursor
                message = "Candy picked up! Move to a neighbor and press SPACE."
            elif selected == cursor:
                selected = None
                message = "Put the candy back down."
            elif is_adjacent(selected, cursor):
                swap_cells(board, selected, cursor)
                score, matched = play_resolution_animation(stdscr, board, cursor, None, moves_left, score, cursor)
                if matched:
                    moves_left -= 1
                    message = "Sweet! Matched some candies!"
                else:
                    swap_cells(board, selected, cursor)  # undo
                    message = "No match there - try a different spot."
                selected = None
            else:
                selected = cursor
                message = "Candy picked up! Move to a neighbor and press SPACE."
        elif key in (ord("q"), ord("Q"), 27):
            return True


def main(stdscr):
    curses.curs_set(0)
    init_colors()
    stdscr.keypad(True)

    if curses.LINES < NEEDED_LINES or curses.COLS < NEEDED_COLS:
        stdscr.erase()
        stdscr.addstr(0, 0, "Please make your terminal window bigger, then restart the game.")
        stdscr.addstr(1, 0, f"Needed: {NEEDED_COLS} columns x {NEEDED_LINES} lines")
        stdscr.addstr(2, 0, f"Current: {curses.COLS} columns x {curses.LINES} lines")
        stdscr.refresh()
        stdscr.getch()
        return

    profile = choose_profile_screen(stdscr)

    while True:
        key = show_leaderboard_screen(stdscr, load_scores())
        if key in (ord("q"), ord("Q"), 27):
            return

        quit_requested = play_round(stdscr, profile)
        if quit_requested:
            return


if __name__ == "__main__":
    curses.wrapper(main)
