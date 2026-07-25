import 'dart:convert';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server/gmail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../sms_sender.dart';
import '../whatsapp_sender.dart';
import 'crm_service.dart';

/// A reusable outreach message. {name} and {company} are filled per lead.
class OutreachTemplate {
  String name;
  String subject;
  String body;
  OutreachTemplate(this.name, this.subject, this.body);

  Map<String, dynamic> toJson() =>
      {'name': name, 'subject': subject, 'body': body};
  factory OutreachTemplate.fromJson(Map<String, dynamic> j) =>
      OutreachTemplate(
          '${j['name'] ?? ''}', '${j['subject'] ?? ''}', '${j['body'] ?? ''}');
}

class TemplateStore {
  static const _key = 'outreach_templates';

  static List<OutreachTemplate> defaults() => [
        OutreachTemplate(
          'Intro',
          'A quick idea for {company}',
          'Hi {name}, I run Agzus Technology Solutions — we build websites and '
              'AI tools for businesses like {company}. Could I share a quick, '
              'free demo?',
        ),
        OutreachTemplate(
          'Follow-up',
          'Following up',
          'Hi {name}, just following up on my earlier note. Happy to show you a '
              'quick demo whenever suits you.',
        ),
        OutreachTemplate(
          'Demo offer',
          'A sample for {company}',
          'Hi {name}, I put together a quick sample for {company}. Want me to '
              'send you the link?',
        ),
      ];

  static Future<List<OutreachTemplate>> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return defaults();
    try {
      final list = (jsonDecode(s) as List)
          .map((e) => OutreachTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
      return list.isEmpty ? defaults() : list;
    } catch (_) {
      return defaults();
    }
  }

  static Future<void> save(List<OutreachTemplate> t) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(t.map((x) => x.toJson()).toList()));
  }
}

/// Fills {name}/{company} for a lead.
String fillTemplate(String s, Lead l) => s
    .replaceAll('{name}', l.name)
    .replaceAll('{company}', l.company.isNotEmpty ? l.company : l.name);

/// Sends outreach on a channel and logs it as a CRM activity.
class Outreach {
  static Future<void> whatsapp(Lead l, String msg) async {
    await WhatsAppSender.openChat(phoneNumber: l.phone, message: msg);
    await CrmService.addActivity(l.id, 'whatsapp', msg);
  }

  static Future<void> sms(Lead l, String msg) async {
    await SmsSender.send(number: l.phone, message: msg);
    await CrmService.addActivity(l.id, 'sms', msg);
  }

  /// Returns true if the email was auto-sent via SMTP, false if the mail app
  /// was opened instead (no Gmail app-password configured).
  static Future<bool> email(Lead l, String subject, String body) async {
    final p = await SharedPreferences.getInstance();
    final gu = p.getString('agent_gmail_user') ?? '';
    final gp = p.getString('agent_gmail_pass') ?? '';
    bool auto = false;
    if (gu.isNotEmpty && gp.isNotEmpty && l.email.isNotEmpty) {
      final m = Message()
        ..from = Address(gu, 'Agzus Technology Solutions')
        ..recipients.add(l.email)
        ..subject = subject
        ..text = body;
      await send(m, gmail(gu, gp));
      auto = true;
    } else {
      await launchUrl(Uri.parse(
          'mailto:${l.email}?subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent(body)}'));
    }
    await CrmService.addActivity(l.id, 'email', body);
    return auto;
  }
}
