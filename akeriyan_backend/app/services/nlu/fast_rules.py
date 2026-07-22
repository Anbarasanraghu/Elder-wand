import re
from datetime import datetime, timedelta

from app.services.contacts import CONTACTS  # shared phone book

_WORD_NUMBERS = {
    'one': '1', 'two': '2', 'three': '3', 'four': '4', 'five': '5',
    'six': '6', 'seven': '7', 'eight': '8', 'nine': '9', 'ten': '10',
    'eleven': '11', 'twelve': '12', 'thirteen': '13', 'fourteen': '14',
    'fifteen': '15', 'twenty': '20', 'thirty': '30', 'forty': '40',
    'forty five': '45', 'fifty': '50', 'sixty': '60',
    'an': '1', 'a': '1', 'half an': '0.5',  # "in an hour", "in a minute"
}


def _words_to_digits(text: str) -> str:
    """Convert 'in two minutes' -> 'in 2 minutes', 'eight pm' -> '8 pm'."""
    t = text
    # longest phrases first so 'forty five' wins over 'forty'
    for word in sorted(_WORD_NUMBERS, key=len, reverse=True):
        t = re.sub(rf'\b{word}\b', _WORD_NUMBERS[word], t)
    return t

def _parse_time(text: str):
    """Find times like '8 pm', '8:30 am', '6 12 pm', 'at 20:00'.
    Handles Whisper quirks: 'p.m', 'a.m.', spaces instead of colons."""

    # Normalize Whisper's meridiem spellings: 'p.m.', 'p.m', 'p m' -> 'pm'
    t = re.sub(r'\bp\.?\s?m\.?\b', 'pm', text)
    t = re.sub(r'\ba\.?\s?m\.?\b', 'am', t)

    # '6 12 pm' or '6:12 pm' or '8 pm'  -> hour, optional minute, meridiem
    m = re.search(r'\b(\d{1,2})(?:[:\s](\d{2}))?\s*(am|pm)\b', t)
    if m:
        hour = int(m.group(1))
        minute = int(m.group(2) or 0)
        meridiem = m.group(3)
        if not (1 <= hour <= 12) or not (0 <= minute <= 59):
            return None
        if meridiem == 'pm' and hour != 12:
            hour += 12
        if meridiem == 'am' and hour == 12:
            hour = 0
    else:
        m24 = re.search(r'\bat\s+(\d{1,2})[:\s](\d{2})\b', t)
        if not m24:
            return None
        hour, minute = int(m24.group(1)), int(m24.group(2))
        if not (0 <= hour <= 23) or not (0 <= minute <= 59):
            return None

    now = datetime.now()
    due = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if due <= now:
        due += timedelta(days=1)
    return due


def _parse_relative(text: str):
    """Find 'in 10 minutes', 'in 2 hours', 'in 0.5 hour'."""
    m = re.search(r'\bin\s+(\d+(?:\.\d+)?)\s+(minute|minutes|min|mins|hour|hours|hr|hrs)\b', text)
    if not m:
        return None
    n = float(m.group(1))
    if n <= 0 or n > 10000:
        return None
    unit = m.group(2)
    delta = timedelta(minutes=n) if unit.startswith('min') else timedelta(hours=n)
    return datetime.now() + delta


def parse(text: str) -> dict:
    t = text.lower().strip().rstrip('.!?')
    t = _words_to_digits(t)


    # ---------- MEMORY: REMEMBER / RECALL / FORGET ----------
    from app.services.memory.store import extract_fact
    _fact = extract_fact(text)
    if _fact and 'remind' not in t:
        return {"intent": "remember", "confidence": 0.9,
                "slots": {"fact": _fact}, "speak": ""}
    if re.search(r'\b(what do you (know|remember)|what have you remembered)\b', t):
        return {"intent": "recall", "confidence": 0.9, "slots": {}, "speak": ""}
    if t.startswith('forget ') or 'forget everything' in t or 'forget that' in t:
        q = re.sub(r'^forget\s+(that\s+)?', '', t).strip()
        return {"intent": "forget", "confidence": 0.9,
                "slots": {"query": q}, "speak": ""}

    # ---------- EMAIL ----------
    if re.search(r'\b(my |new |any )?e-?mails?\b', t) and \
       re.search(r'\b(read|check|any|new|show|summar)', t):
        return {"intent": "email_summary", "confidence": 0.9,
                "slots": {}, "speak": ""}

    # ---------- CRM: ADD LEAD ----------
    m = re.match(r'^(?:add|new|log|create)\s+(?:a\s+)?lead\b[:\s]*(.*)$', t)
    if m:
        return {"intent": "add_lead", "confidence": 0.9,
                "slots": {"raw": m.group(1).strip() or text}, "speak": ""}

    # ---------- MORNING BRIEFING ----------
    if 'briefing' in t or 'brief me' in t or 'my morning' in t or \
       re.fullmatch(r'good morning( akeriyan)?', t):
        return {"intent": "briefing", "confidence": 0.9, "slots": {}, "speak": ""}

    # ---------- REMINDERS ----------
    if 'remind me' in t or t.startswith('reminder'):
        recurrence = 'FREQ=DAILY' if re.search(r'\bevery\s*day\b|\bdaily\b', t) else None
        due = _parse_time(t) or _parse_relative(t)

        # extract the task text between "remind me (to)" and the time part
        task = re.sub(r'^.*?remind me( to)?\s*', '', t)
        task = re.sub(r'\b(at\s+|in\s+)?\d{1,2}([:\s]\d{2})?\s*(a\.?\s?m\.?|p\.?\s?m\.?)\b.*$', '', task)
        task = re.sub(r'\bin\s+\d+\s+(minutes?|hours?)\b.*$', '', task)
        task = re.sub(r'\bevery\s*day\b|\bdaily\b', '', task).strip() or 'your task'

        if due:
            when = due.strftime('%I:%M %p').lstrip('0')
            speak = f"Reminder set for {when}"
            if recurrence:
                speak += ", every day"
            speak += f": {task}. Done, Anbarasan."
        else:
            speak = f"I heard the reminder '{task}', but I couldn't find a time. Please say a time like 8 PM."

        return {
            "intent": "create_reminder",
            "confidence": 0.9 if due else 0.6,
            "slots": {
                "text": task,
                "time": due.isoformat() if due else None,
                "recurrence": recurrence,
            },
            "speak": speak,
        }

    # ---------- TIMER ----------
    if 'timer' in t or re.search(r'\bset (a|an)\b.*\b(minute|second|hour)', t):
        from app.services.skills.calc import parse_seconds
        secs = parse_seconds(t)
        if secs:
            mins = secs // 60
            human = f"{mins} minute{'s' if mins != 1 else ''}" if mins else f"{secs} seconds"
            return {
                "intent": "set_timer",
                "confidence": 0.9,
                "slots": {"seconds": secs},
                "speak": f"Timer set for {human}.",
            }

    # ---------- READ NOTIFICATIONS ----------
    if re.search(r'\b(read|latest|last|my)\b.*\bnotification', t) or \
       'notifications' in t:
        kind = 'all' if 'all' in t else 'latest'
        return {
            "intent": "read_notifications",
            "confidence": 0.9,
            "slots": {"kind": kind},
            "speak": "",  # phone fills this from the notification log
        }

    # ---------- PHONE CALL ----------
    m = re.search(r'\b(?:call|dial|phone|ring)\s+([a-z]+)', t)
    if m and 'whatsapp' not in t:
        name = m.group(1)
        if name not in ('me', 'up', 'the', 'a', 'back'):
            number = CONTACTS.get(name)
            if number:
                return {"intent": "phone_call", "confidence": 0.9,
                        "slots": {"contact": name, "number": number},
                        "speak": f"Calling {name}."}
            return {"intent": "phone_call", "confidence": 0.6,
                    "slots": {"contact": name, "number": None},
                    "speak": f"I don't have a number saved for {name}."}

    # ---------- FLASHLIGHT ----------
    if 'flashlight' in t or 'torch' in t:
        state = 'off' if 'off' in t or 'turn out' in t else 'on'
        return {"intent": "toggle_flashlight", "confidence": 0.95,
                "slots": {"state": state},
                "speak": f"Turning the flashlight {state}."}

    # ---------- WEATHER ----------
    if 'weather' in t or 'temperature' in t or 'how hot' in t or 'how cold' in t or \
       'will it rain' in t or 'is it raining' in t:
        cm = re.search(r'\bin\s+([a-z ]+)$', t)
        city = cm.group(1).strip() if cm else None
        return {"intent": "weather", "confidence": 0.9,
                "slots": {"city": city}, "speak": ""}

    # ---------- NEWS ----------
    if 'news' in t or 'headlines' in t:
        tm = re.search(r'\b(?:about|on)\s+(.+)$', t)
        topic = tm.group(1).strip() if tm else None
        return {"intent": "news", "confidence": 0.9,
                "slots": {"topic": topic}, "speak": ""}

    # ---------- LIVE AGENT (real-time monitor) ----------
    if 'live agent' in t or 'live price' in t or 'eye on' in t or \
       (('monitor' in t or 'watch' in t or 'track' in t)
        and any(w in t for w in ('bitcoin', 'ethereum', 'crypto', 'gold',
                                 'silver', 'forex', 'market', 'stock', 'price',
                                 'eurusd', 'usdinr', 'btc', 'eth', 'solana',
                                 'dollar', 'nifty'))):
        sm = re.search(r'\b(?:monitor|watch|track|agent on|live)\s+([a-z ]+?)'
                       r'(?:\s+live| now| please|$)', t)
        symbol = sm.group(1).strip() if sm else t
        return {"intent": "watch_market", "confidence": 0.9,
                "slots": {"symbol": symbol},
                "speak": "Starting the live agent."}

    # ---------- PRO / FULL TERMINAL ANALYSIS ----------
    if 'full analysis' in t or 'pro analysis' in t or 'deep analysis' in t or \
       'complete analysis' in t or 'liquidity' in t or 'your decision' in t or \
       'trade decision' in t or 'should i buy' in t or 'should i sell' in t or \
       ('analyze' in t and ('news' in t or 'everything' in t or 'fully' in t)):
        sm = re.search(r'\b(?:analysis of|analyze|about|on|for|buy|sell)\s+'
                       r'([a-z ]+?)(?:\s+full| fully| now| please| analysis|$)', t)
        symbol = sm.group(1).strip() if sm else t
        return {"intent": "pro_analysis", "confidence": 0.92,
                "slots": {"symbol": symbol}, "speak": ""}

    # ---------- SCALPING / SMART-MONEY SETUP ----------
    if 'scalp' in t or 'scalping' in t or 'order block' in t or \
       'trade setup' in t or 'entry setup' in t or \
       'support and resistance' in t or 'multi timeframe' in t or \
       'multi-timeframe' in t or 'one minute setup' in t or \
       '1 minute setup' in t or 'smart money' in t:
        sm = re.search(r'\b(?:scalp|setup|for|on|of|block[s]?|analysis of)\s+'
                       r'([a-z ]+?)(?:\s+scalp| setup| now| please|$)', t)
        symbol = sm.group(1).strip() if sm else t
        return {"intent": "scalp_analysis", "confidence": 0.92,
                "slots": {"symbol": symbol}, "speak": ""}

    # ---------- CRYPTO / MARKET ANALYSIS ----------
    from app.services.skills.trading import resolve_symbol
    _coin_words = ('bitcoin', 'ethereum', 'crypto', 'coin', 'btc', 'eth',
                   'solana', 'dogecoin', 'binance coin', 'ripple', 'xrp',
                   'cardano', 'litecoin', 'chainlink', 'polkadot', 'avalanche')
    _market_words = ('analyze', 'analyse', 'analysis', 'price of', 'chart',
                     'market', 'trading', 'how is', "how's", 'rsi', 'trend')
    if any(w in t for w in _coin_words) and \
       (any(w in t for w in _market_words) or 'price' in t):
        # pull the phrase that likely names the coin
        cm = re.search(r'\b(?:analyze|analyse|analysis of|price of|chart of|'
                       r'how is|how\'s|about)\s+([a-z ]+)', t)
        candidate = cm.group(1).strip() if cm else t
        symbol = resolve_symbol(candidate) or resolve_symbol(t)
        interval = '1d' if 'day' in t or 'daily' in t else \
                   ('4h' if '4 hour' in t else '1h')
        return {"intent": "market_analysis", "confidence": 0.9,
                "slots": {"symbol": candidate, "interval": interval,
                          "resolved": symbol}, "speak": ""}

    # ---------- GOLD / METALS / FOREX ----------
    _mf = ('gold', 'silver', 'platinum', 'palladium', 'copper', 'crude',
           'crude oil', 'brent', 'natural gas', 'forex', 'exchange rate',
           'dollar index', 'dxy', 'euro', 'yen', 'pound', 'rupee',
           'eurusd', 'gbpusd', 'usdjpy', 'usdinr', 'dollar rupee',
           'dollar to rupee', 'usd to inr', 'dollar yen', 'euro dollar')
    if any(w in t for w in _mf):
        interval = '1d'
        if 'week' in t or 'weekly' in t:
            interval = '1w'
        elif 'month' in t or 'monthly' in t:
            interval = '1mo'
        elif 'hour' in t or 'today' in t or 'intraday' in t:
            interval = '1d'
        return {"intent": "stock_analysis", "confidence": 0.9,
                "slots": {"symbol": t, "interval": interval}, "speak": ""}

    # ---------- STOCKS ----------
    if 'stock' in t or 'share price' in t or 'shares' in t or \
       re.search(r'\b(nifty|sensex|nasdaq|dow jones)\b', t):
        sm = re.search(r'\b(?:of|for|is|about)\s+([a-z .]+?)(?:\s+stock| share| doing|$)', t)
        candidate = sm.group(1).strip() if sm else re.sub(
            r'\b(stock|share price|shares|price|of|the|how|is|whats|what\'s|doing)\b',
            '', t).strip()
        return {"intent": "stock_analysis", "confidence": 0.85,
                "slots": {"symbol": candidate or t, "interval": "1d"},
                "speak": ""}

    # ---------- CALCULATOR ----------
    if re.search(r"\b(calculate|what is|whats|what's|how much is)\b.*\d", t) or \
       re.search(r'\d+\s*(plus|minus|times|multiplied|divided|into|percent|power)\b', t):
        return {"intent": "math", "confidence": 0.85,
                "slots": {"expression": t}, "speak": ""}

    # ---------- WHATSAPP ----------
    if 'whatsapp' in t or ('message' in t and ('send' in t or 'tell' in t)) \
       or t.startswith('tell ') or t.startswith('text '):
        name = None
        message = None

        # Find the contact after "to <name>" or "tell <name>" or "text <name>"
        nm = re.search(r'\b(?:to|tell|text|message)\s+([a-z]+)', t)
        if nm:
            candidate = nm.group(1)
            # skip filler words that aren't names
            if candidate not in ('a', 'the', 'whatsapp', 'message', 'him', 'her', 'them'):
                name = candidate
            else:
                nm2 = re.search(r'\bto\s+([a-z]+)', t)
                if nm2 and nm2.group(1) not in ('the', 'a'):
                    name = nm2.group(1)

        # Find the message after saying/that/was/:
        mm = re.search(r'(?:saying|message was|that says?|:|that)\s+(.+)$', t)
        if mm:
            message = mm.group(1).strip()
        else:
            # fallback: text after the name
            if name:
                after = re.search(rf'\b{name}\b\s+(.+)$', t)
                if after:
                    message = re.sub(r'^(and then the message was|saying|that)\s+',
                                     '', after.group(1)).strip()

        if not name:
            return {"intent": "whatsapp_send", "confidence": 0.4,
                    "slots": {"contact": None, "message": message, "number": None},
                    "speak": "Who should I message?"}

        number = CONTACTS.get(name)
        if not number:
            return {"intent": "whatsapp_send", "confidence": 0.5,
                    "slots": {"contact": name, "message": message, "number": None},
                    "speak": f"I don't have a number saved for {name}."}

        if not message:
            return {"intent": "whatsapp_send", "confidence": 0.6,
                    "slots": {"contact": name, "message": None, "number": number},
                    "speak": f"What should I tell {name}?"}

        return {"intent": "whatsapp_send", "confidence": 0.9,
                "slots": {"contact": name, "message": message, "number": number},
                "speak": f"Opening WhatsApp to message {name}."}

    # ---------- OPEN APP ----------
    m = re.search(r'\bopen\s+(.+)$', t)
    if m:
        app_name = m.group(1).strip()
        return {
            "intent": "open_app",
            "confidence": 0.9,
            "slots": {"app": app_name},
            "speak": f"Opening {app_name}.",
        }

    # ---------- TIME ----------
    if 'what time' in t or "what's the time" in t or 'time is it' in t:
        now = datetime.now().strftime('%I:%M %p').lstrip('0')
        return {
            "intent": "smalltalk",
            "confidence": 1.0,
            "slots": {},
            "speak": f"It is {now}, Anbarasan.",
        }

    # ---------- GREETINGS ----------
    if re.fullmatch(r'(hi|hello|hey)( akeriyan)?', t):
        return {
            "intent": "smalltalk",
            "confidence": 1.0,
            "slots": {},
            "speak": "Yes, Anbarasan. I am listening.",
        }

    # ---------- UNKNOWN (let the LLM brain take over) ----------
    return {
        "intent": "unknown",
        "confidence": 0.0,
        "slots": {"text": text},
        "speak": "I heard you, but I don't know that command yet.",
    }
