#include "zwischenablage_html_plugin.h"

// Muss vor anderen Windows-Kopfdateien stehen.
#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <cstring>
#include <memory>
#include <string>
#include <variant>

namespace zwischenablage_html {

namespace {

const std::string* Text(const flutter::EncodableMap& map, const char* name) {
  auto it = map.find(flutter::EncodableValue(name));
  if (it == map.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

// Kopiert [bytes] in globalen Speicher, wie SetClipboardData ihn verlangt.
// Gehört nach erfolgreichem SetClipboardData dem System.
HGLOBAL Global(const void* bytes, size_t laenge) {
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, laenge);
  if (h == nullptr) return nullptr;
  void* p = GlobalLock(h);
  if (p == nullptr) {
    GlobalFree(h);
    return nullptr;
  }
  memcpy(p, bytes, laenge);
  GlobalUnlock(h);
  return h;
}

bool Setzen(UINT format, HGLOBAL h) {
  if (h == nullptr) return false;
  if (SetClipboardData(format, h) == nullptr) {
    GlobalFree(h);
    return false;
  }
  return true;
}

}  // namespace

// static
void ZwischenablageHtmlPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "zwischenablage_html",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ZwischenablageHtmlPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ZwischenablageHtmlPlugin::ZwischenablageHtmlPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

ZwischenablageHtmlPlugin::~ZwischenablageHtmlPlugin() {}

void ZwischenablageHtmlPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() != "kopieren") {
    result->NotImplemented();
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  const std::string* html = args ? Text(*args, "html") : nullptr;
  const std::string* text = args ? Text(*args, "text") : nullptr;
  if (html == nullptr || text == nullptr) {
    result->Error("argumente", "html und text verlangt");
    return;
  }

  // „HTML Format" ist UTF-8 mit Kopf (cfHtml auf der Dart-Seite), Text geht
  // als UTF-16. Beide mit abschließender Null.
  int laenge = MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, nullptr, 0);
  std::wstring breit(laenge > 0 ? laenge : 1, L'\0');
  if (laenge > 0) {
    MultiByteToWideChar(CP_UTF8, 0, text->c_str(), -1, breit.data(), laenge);
  }

  // Ohne Fenster als Besitzer scheitert SetClipboardData nach EmptyClipboard.
  HWND fenster = GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
  // Hält ein anderes Programm die Zwischenablage gerade offen, kurz warten.
  bool offen = false;
  for (int i = 0; i < 10 && !(offen = OpenClipboard(fenster) != 0); i++) {
    Sleep(20);
  }
  if (!offen) {
    result->Error("belegt", "Zwischenablage von einem anderen Programm belegt");
    return;
  }
  EmptyClipboard();
  bool ok = Setzen(RegisterClipboardFormatW(L"HTML Format"),
                   Global(html->c_str(), html->size() + 1)) &&
            Setzen(CF_UNICODETEXT,
                   Global(breit.c_str(), breit.size() * sizeof(wchar_t)));
  CloseClipboard();
  if (ok) {
    result->Success();
  } else {
    result->Error("speicher", "Zwischenablage ließ sich nicht setzen");
  }
}

}  // namespace zwischenablage_html
