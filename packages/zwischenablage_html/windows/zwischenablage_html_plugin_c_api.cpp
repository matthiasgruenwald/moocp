#include "include/zwischenablage_html/zwischenablage_html_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "zwischenablage_html_plugin.h"

void ZwischenablageHtmlPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  zwischenablage_html::ZwischenablageHtmlPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
