import 'package:web/web.dart' as web;

void setDocumentLanguage(String language) {
  web.document.documentElement?.setAttribute('lang', language);
}
