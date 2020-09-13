local dir
if dir=$(compgen -G 'root/usr/lib*/firefox/browser')
then
        dir="${dir%%$'\n'*}/defaults/preferences"
        test -h "$dir" -a "x${dir/\/browser}" = "xroot$(readlink "$dir")" &&
        ln -fns ../../defaults/preferences "$dir"
        mkdir -p "$dir"

        # Disable things that store and send your confidential information.
        cat << 'EOF' > "$dir/privacy.js"
// Opt out of allowing Mozilla to install random studies.
pref("app.shield.optoutstudies.enabled", false);
// Disable the beacon API for analytical trash.
pref("beacon.enabled", false);
// Don't recommend things.
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
// Disable spam-tier nonsense on new tabs.
pref("browser.newtabpage.enabled", false);
// Don't download autocomplete URLs.
pref("browser.urlbar.speculativeConnect.enabled", false);
// Don't send information to Mozilla.
pref("datareporting.healthreport.uploadEnabled", false);
// Never give up laptop battery information.
pref("dom.battery.enabled", false);
// Remove useless Pocket stuff.
pref("extensions.pocket.enabled", false);
// Never send location data.
pref("geo.enabled", false);
// Send DNT all the time.
pref("privacy.donottrackheader.enabled", true);
// Prevent various cross-domain tracking methods.
pref("privacy.firstparty.isolate", true);
// Never try to save credentials.
pref("signon.rememberSignons", false);
EOF

        # Try to fix many UI "improvements" and be more usable in general.
        cat << 'EOF' > "$dir/usability.js"
// Fix the Ctrl+Tab behavior.
pref("browser.ctrlTab.recentlyUsedOrder", false);
// Never open more browser windows.
pref("browser.link.open_newwindow.restriction", 0);
// Fix distribution search plugins.
pref("browser.search.modernConfig", false);
// Include a sensible search bar.
pref("browser.search.openintab", true);
pref("browser.search.suggest.enabled", false);
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
// Enable some mildly useful developer tools.
pref("devtools.command-button-rulers.enabled", true);
pref("devtools.command-button-scratchpad.enabled", true);
pref("devtools.command-button-screenshot.enabled", true);
// Make the developer tools frame match the browser theme.
pref("devtools.theme", "dark");
// Display when messages are logged.
pref("devtools.webconsole.timestampMessages", true);
// Shut up.
pref("general.warnOnAboutConfig", false);
// Stop stretching PDFs off the screen for no reason.
pref("pdfjs.defaultZoomValue", "page-fit");
// Prefer the PDF outline display.
pref("pdfjs.sidebarViewOnLoad", 2);
// Guess that odd-spread is going to be the most common case.
pref("pdfjs.spreadModeOnLoad", 1);
// Make widgets on web pages match the rest of the desktop.
pref("widget.content.allow-gtk-dark-theme", true);
EOF

        # Try to install a search engine for startpage.com by default.
        dir="${dir%%/browser/*}/distribution/searchplugins/common"
        mkdir -p "$dir"
        curl -L 'https://www.startpage.com/en/opensearch.xml' > "$dir/startpage.xml" &&
        test x$(sha256sum "$dir/startpage.xml" | sed -n '1s/ .*//p') = \
            x50c2b828d22f13dde32662db8796fb670d389651ad27a8946e30363fd5beecc7 ||
        rm -f "$dir/startpage.xml"

        # Mozilla is weird about some settings.  Write a policy file for them.
        cat << 'EOF' > "${dir%/searchplugins/common}/policies.json"
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
