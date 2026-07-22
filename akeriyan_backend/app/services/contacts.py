"""Your phone book. Add real people here as 'name': 'country+number'."""

CONTACTS: dict[str, str] = {
    "aravind": "918072651549",
    "amma": "918682838242",
    # add your real contacts here, e.g.  "appa": "9198xxxxxxxx",
}


def resolve(name: str | None) -> str | None:
    """Look up a spoken name -> phone number (case/space insensitive)."""
    if not name:
        return None
    key = name.strip().lower()
    if key in CONTACTS:
        return CONTACTS[key]
    # tolerate 'to amma', partial matches
    for n, num in CONTACTS.items():
        if n in key or key in n:
            return num
    return None
