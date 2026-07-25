import 'crm_service.dart';

/// Builds a polished, self-contained 1-page demo website (HTML) from a lead's
/// details — a shareable pitch you can send to win the deal.
class DemoBuilder {
  static const _services = <String, List<String>>{
    'gym': ['Personal Training', 'Group Classes', 'Nutrition Coaching', 'Modern Equipment'],
    'fitness': ['Personal Training', 'Group Classes', 'Nutrition Coaching', 'Modern Equipment'],
    'dentist': ['Dental Check-ups', 'Teeth Whitening', 'Implants', 'Braces & Aligners'],
    'doctor': ['Consultation', 'Diagnostics', 'Treatment Plans', 'Follow-up Care'],
    'clinic': ['Consultation', 'Diagnostics', 'Treatments', 'Health Packages'],
    'restaurant': ['Dine-in', 'Takeaway', 'Party Orders', 'Online Delivery'],
    'cafe': ['Fresh Coffee', 'All-day Breakfast', 'Desserts', 'Cozy Ambience'],
    'bakery': ['Fresh Bakes', 'Custom Cakes', 'Party Orders', 'Same-day Delivery'],
    'salon': ['Haircut & Styling', 'Colouring', 'Spa & Facials', 'Bridal Makeup'],
    'beauty': ['Skin Care', 'Hair Care', 'Spa & Facials', 'Bridal Packages'],
    'hairdresser': ['Haircut & Styling', 'Colouring', 'Beard Grooming', 'Kids Cuts'],
    'hotel': ['Rooms & Suites', 'In-house Dining', 'Events & Weddings', '24/7 Service'],
    'school': ['Expert Faculty', 'Modern Curriculum', 'Sports & Arts', 'Safe Campus'],
    'pharmacy': ['Prescriptions', 'Home Delivery', 'Health Products', 'Wellness Advice'],
  };

  static List<String> _servicesFor(String category) {
    final c = category.toLowerCase();
    for (final e in _services.entries) {
      if (c.contains(e.key)) return e.value;
    }
    return const [
      'Quality Service',
      'Experienced Team',
      'Fair Pricing',
      'Trusted Locally'
    ];
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // deterministic accent hue from the business name (variety across leads)
  static int _hue(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0xffffff;
    }
    return h % 360;
  }

  static String build(Lead l) {
    final name = _esc(l.name.isEmpty ? 'Your Business' : l.name);
    final cat = l.category.isEmpty ? 'local business' : _esc(l.category);
    final city = l.address.contains(',')
        ? _esc(l.address.split(',').last.trim())
        : 'your city';
    final phone = l.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final email = _esc(l.email);
    final addr = _esc(l.address);
    final services = _servicesFor(l.category);
    final hue = _hue(l.name);
    final hue2 = (hue + 40) % 360;

    final serviceCards = services
        .map((s) => '''
      <div class="card">
        <div class="dot"></div>
        <h3>${_esc(s)}</h3>
        <p>Professional ${_esc(s.toLowerCase())} you can rely on.</p>
      </div>''')
        .join('\n');

    final callBtn = phone.isNotEmpty
        ? '<a class="btn" href="tel:$phone">Call now</a>'
        : '';
    final waBtn = phone.isNotEmpty
        ? '<a class="btn ghost" href="https://wa.me/$phone">WhatsApp</a>'
        : '';
    final mapLink = addr.isNotEmpty
        ? '<a href="https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(l.address)}" target="_blank">$addr</a>'
        : '';

    return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$name</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Sora:wght@600;800&family=Inter:wght@400;500&display=swap" rel="stylesheet">
<style>
  :root{ --a:hsl($hue 80% 55%); --b:hsl($hue2 80% 50%); --ink:#14181f; --muted:#5b6675; }
  *{box-sizing:border-box;margin:0} html{scroll-behavior:smooth}
  body{font-family:Inter,system-ui,sans-serif;color:var(--ink);background:#fff;line-height:1.6}
  h1,h2,h3{font-family:Sora,sans-serif;line-height:1.15}
  .wrap{max-width:1000px;margin:0 auto;padding:0 22px}
  .hero{background:linear-gradient(135deg,var(--a),var(--b));color:#fff;padding:90px 0 80px;text-align:center}
  .badge{display:inline-block;background:rgba(255,255,255,.18);padding:6px 14px;border-radius:100px;font-size:13px;letter-spacing:.5px;text-transform:capitalize;margin-bottom:18px}
  .hero h1{font-size:clamp(34px,7vw,60px);font-weight:800}
  .hero p{opacity:.95;font-size:clamp(15px,2.4vw,20px);margin:14px auto 0;max-width:620px}
  .cta{margin-top:28px;display:flex;gap:12px;justify-content:center;flex-wrap:wrap}
  .btn{background:#fff;color:var(--ink);padding:13px 24px;border-radius:12px;font-weight:600;text-decoration:none;box-shadow:0 8px 24px rgba(0,0,0,.15)}
  .btn.ghost{background:rgba(255,255,255,.14);color:#fff;box-shadow:none;border:1px solid rgba(255,255,255,.4)}
  section{padding:64px 0}
  .eyebrow{color:var(--a);font-weight:600;letter-spacing:1px;text-transform:uppercase;font-size:13px;text-align:center}
  section h2{font-size:clamp(26px,4vw,38px);text-align:center;margin-top:6px;font-weight:800}
  .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:18px;margin-top:34px}
  .card{background:#f7f8fb;border:1px solid #eceef3;border-radius:18px;padding:24px}
  .card .dot{width:34px;height:34px;border-radius:10px;background:linear-gradient(135deg,var(--a),var(--b));margin-bottom:14px}
  .card h3{font-size:18px;margin-bottom:6px}
  .card p{color:var(--muted);font-size:14px}
  .about{background:#0e1116;color:#eef1f6}
  .about p{color:#aeb6c2;max-width:640px;margin:16px auto 0;text-align:center;font-size:16px}
  .contact .row{display:flex;justify-content:center;gap:12px;flex-wrap:wrap;margin-top:26px}
  .pill{background:#f2f4f8;border-radius:12px;padding:14px 20px;font-weight:500}
  .pill a{color:var(--a);text-decoration:none}
  footer{background:#0a0c10;color:#8b939d;text-align:center;padding:30px 0;font-size:13px}
  footer b{color:#dfe9fb}
</style>
</head>
<body>
  <header class="hero">
    <div class="wrap">
      <span class="badge">$cat</span>
      <h1>$name</h1>
      <p>Quality $cat in $city — trusted by the community, ready to serve you.</p>
      <div class="cta">$callBtn $waBtn</div>
    </div>
  </header>

  <section>
    <div class="wrap">
      <div class="eyebrow">What we offer</div>
      <h2>Our Services</h2>
      <div class="grid">
$serviceCards
      </div>
    </div>
  </section>

  <section class="about">
    <div class="wrap">
      <div class="eyebrow">About us</div>
      <h2 style="color:#fff">Why choose $name</h2>
      <p>We're a dedicated $cat serving $city with care, quality and a personal
      touch. Our team is committed to giving every customer a great experience —
      come see the difference for yourself.</p>
    </div>
  </section>

  <section class="contact">
    <div class="wrap" style="text-align:center">
      <div class="eyebrow">Get in touch</div>
      <h2>Visit or Call Us</h2>
      <div class="row">
        ${phone.isNotEmpty ? '<div class="pill">📞 <a href="tel:$phone">$phone</a></div>' : ''}
        ${email.isNotEmpty ? '<div class="pill">✉️ <a href="mailto:$email">$email</a></div>' : ''}
        ${mapLink.isNotEmpty ? '<div class="pill">📍 $mapLink</div>' : ''}
      </div>
    </div>
  </section>

  <footer>
    <div class="wrap">Free demo site crafted by <b>Agzus Technology Solutions</b> — want a site like this? Let's talk.</div>
  </footer>
</body>
</html>''';
  }
}
