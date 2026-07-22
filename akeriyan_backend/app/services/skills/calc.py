"""Safe calculator + timer parsing. No eval() — a tiny locked-down AST walker."""
import ast
import operator
import re

_OPS = {
    ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
    ast.Div: operator.truediv, ast.Pow: operator.pow, ast.Mod: operator.mod,
    ast.USub: operator.neg, ast.UAdd: operator.pos,
    ast.FloorDiv: operator.floordiv,
}


def _eval(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
        return _OPS[type(node.op)](_eval(node.left), _eval(node.right))
    if isinstance(node, ast.UnaryOp) and type(node.op) in _OPS:
        return _OPS[type(node.op)](_eval(node.operand))
    raise ValueError("unsupported expression")


def calculate(expression: str) -> str:
    """Turn spoken math into a number. '5 times 12 plus 3' -> 'That is 63.'"""
    expr = expression.lower()
    words = {
        "plus": "+", "add": "+", "minus": "-", "subtract": "-",
        "times": "*", "multiplied by": "*", "multiply by": "*", "x": "*",
        "divided by": "/", "over": "/", "into": "*",
        "percent of": "/100*", "power of": "**", "to the power of": "**",
        "squared": "**2", "modulo": "%", "mod": "%",
    }
    for w, sym in sorted(words.items(), key=lambda kv: -len(kv[0])):
        expr = expr.replace(w, sym)
    expr = re.sub(r"[^0-9+\-*/%.()\s]", "", expr).strip()
    if not expr:
        return "That doesn't look like a calculation."
    try:
        value = _eval(ast.parse(expr, mode="eval").body)
        if isinstance(value, float) and value.is_integer():
            value = int(value)
        elif isinstance(value, float):
            value = round(value, 4)
        return f"That is {value}."
    except Exception:
        return "I couldn't work that one out."


def parse_seconds(text: str) -> int | None:
    """'set a 10 minute timer' / 'timer for 90 seconds' -> total seconds."""
    total = 0
    found = False
    for num, unit in re.findall(r"(\d+(?:\.\d+)?)\s*(hour|hours|hr|minute|minutes|min|second|seconds|sec)", text.lower()):
        found = True
        n = float(num)
        if unit.startswith("h"):
            total += n * 3600
        elif unit.startswith(("m", "min")) and "sec" not in unit:
            total += n * 60
        else:
            total += n
    return int(total) if found and total > 0 else None
