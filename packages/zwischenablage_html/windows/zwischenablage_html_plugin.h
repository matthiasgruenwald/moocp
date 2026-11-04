#ifndef FLUTTER_PLUGIN_ZWISCHENABLAGE_HTML_PLUGIN_H_
#define FLUTTER_PLUGIN_ZWISCHENABLAGE_HTML_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace zwischenablage_html {

class ZwischenablageHtmlPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit ZwischenablageHtmlPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~ZwischenablageHtmlPlugin();

  ZwischenablageHtmlPlugin(const ZwischenablageHtmlPlugin&) = delete;
  ZwischenablageHtmlPlugin& operator=(const ZwischenablageHtmlPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  // Für das Fenster, dem die Zwischenablage gehört.
  flutter::PluginRegistrarWindows* registrar_;
};

}  // namespace zwischenablage_html

#endif  // FLUTTER_PLUGIN_ZWISCHENABLAGE_HTML_PLUGIN_H_
