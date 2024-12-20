# SPDX-License-Identifier: GPL-3.0-or-later
local dir
if dir=$(compgen -G 'root/usr/lib*/firefox/browser')
then
        dir="${dir%%$'\n'*}/defaults/preferences"
        [[ -h $dir && ${dir/\/browser} == root$(readlink "$dir") ]] &&
        ln -fns ../../defaults/preferences "$dir"
        mkdir -p "$dir"

        # Disable things that store and send your confidential information.
        cat << 'EOF' > "$dir/privacy.js"
// Prevent Mozilla from experimenting on default settings.
pref("app.normandy.enabled", false);
// Opt out of allowing Mozilla to install random studies.
pref("app.shield.optoutstudies.enabled", false);
// Disable the beacon API for analytical trash.
pref("beacon.enabled", false);
// Don't recommend things.
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
// Disable spam-tier nonsense on new tabs.
pref("browser.newtabpage.enabled", false);
// Don't try to predict search terms, and don't prioritize them over history.
pref("browser.search.suggest.enabled", false);
pref("browser.urlbar.quicksuggest.enabled", false);
pref("browser.urlbar.showSearchSuggestionsFirst", false);
pref("browser.urlbar.suggest.recentsearches", false);
pref("browser.urlbar.suggest.trending", false);
// Don't download autocomplete URLs.
pref("browser.urlbar.speculativeConnect.enabled", false);
// Don't send URL bar keystrokes to advertisers.
pref("browser.urlbar.suggest.quicksuggest", false);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
// Don't send information to Mozilla.
pref("datareporting.healthreport.uploadEnabled", false);
// Never give up laptop battery information.
pref("dom.battery.enabled", false);
// Disable "privacy preserving" tracking.
pref("dom.private-attribution.submission.enabled", false);
// Require HTTPS by default.
pref("dom.security.https_only_mode", true);
// Remove useless Pocket stuff.
pref("extensions.pocket.enabled", false);
// Never send location data.
pref("geo.enabled", false);
// Disable executing scripts in PDFs by default again.
pref("pdfjs.enableScripting", false);
// Send DNT all the time.
pref("privacy.donottrackheader.enabled", true);
// Prevent various cross-domain tracking methods.
pref("privacy.firstparty.isolate", true);
// Never try to save credentials.
pref("signon.rememberSignons", false);
EOF

        # Try to fix many UI "improvements" and be more usable in general.
        cat << 'EOF' > "$dir/usability.js"
// Don't yell at the user for configuring the browser.
pref("browser.aboutConfig.showWarning", false);
pref("general.warnOnAboutConfig", false);
// Fix the Ctrl+Tab behavior.
pref("browser.ctrlTab.recentlyUsedOrder", false);
// Never open more browser windows.
pref("browser.link.open_newwindow.restriction", 0);
// Don't make notification buttons about new browser features.
pref("browser.messaging-system.whatsNewPanel.enabled", false);
// Include a sensible search bar.
pref("browser.search.openintab", true);
pref("browser.search.widget.inNavBar", true);
// Restore sessions instead of starting at home, and make the home page blank.
pref("browser.startup.homepage", "about:blank");
pref("browser.startup.page", 3);
// Fit more stuff on the screen.
pref("browser.tabs.drawInTitlebar", true);
pref("browser.uidensity", 1);
// Disable obnoxious visual spam when selecting the URL.
pref("browser.urlbar.openViewOnFocus", false);
// Stop hiding protocols.
pref("browser.urlbar.trimURLs", false);
// Don't ask for confirmation to quit with the keyboard.
pref("browser.warnOnQuitShortcut", false);
// Enable some mildly useful developer tools.
pref("devtools.command-button-rulers.enabled", true);
pref("devtools.command-button-scratchpad.enabled", true);
pref("devtools.command-button-screenshot.enabled", true);
// Make the developer tools frame match the browser theme.
pref("devtools.theme", "dark");
// Display when messages are logged.
pref("devtools.webconsole.timestampMessages", true);
// Stop stretching PDFs off the screen for no reason.
pref("pdfjs.defaultZoomValue", "page-fit");
// Prefer the PDF outline display.
pref("pdfjs.sidebarViewOnLoad", 2);
// Guess that odd-spread is going to be the most common case.
pref("pdfjs.spreadModeOnLoad", 1);
// Make widgets on web pages match the rest of the desktop.
pref("widget.content.allow-gtk-dark-theme", true);
EOF

        # Mozilla is weird about some settings.  Write a policy file for them.
        cat << 'EOF' > "${dir%%/browser/*}/distribution/policies.json"
{
  "policies": {
    "DisableAppUpdate": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DisableTelemetry": true,
    "DisplayBookmarksToolbar": false,
    "DisplayMenuBar": false,
    "DontCheckDefaultBrowser": true,
    "EnableTrackingProtection": {
      "Cryptomining": true,
      "Fingerprinting": true,
      "Value": true,
      "Locked": false
    },
    "FirefoxHome": {
      "Highlights": false,
      "Pocket": false,
      "Search": false,
      "Snippets": false,
      "TopSites": false,
      "Locked": false
    },
    "Homepage": {
      "StartPage": "previous-session",
      "URL": "about:blank",
      "Locked": false
    },
    "NewTabPage": false,
    "OverrideFirstRunPage": "",
    "OverridePostUpdatePage": "",
    "SearchBar": "separate",
    "SearchSuggestEnabled": false
  }
}
EOF
fi
