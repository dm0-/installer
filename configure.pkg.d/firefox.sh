local dir
if dir=$(compgen -G 'root/usr/lib*/firefox/browser/defaults/preferences')
then
        # Disable things that store and send your confidential information.
        cat << 'EOF' > "${dir%%$'\n'*}/privacy.js"
// Opt out of allowing Mozilla to install random studies.
pref("app.shield.optoutstudies.enabled", false);
// Disable the beacon API for analytical trash.
pref("beacon.enabled", false);
// Don't recommend things.
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
// Disable spam-tier nonsense on new tabs.
pref("browser.newtabpage.enabled", false);
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
        cat << 'EOF' > "${dir%%$'\n'*}/usability.js"
// Fix the Ctrl+Tab behavior.
pref("browser.ctrlTab.recentlyUsedOrder", false);
// Never open more browser windows.
pref("browser.link.open_newwindow.restriction", 0);
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
fi
