{ pkgs, inputs, ... }:

let
  firefox-addons = inputs.firefox-addons.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.firefox = {
    enable = true;

    profiles.default = {
      isDefault = true;

      bookmarks = {
        force = true;
        settings = [
          {
            name = "d.rymcg.tech";
            url = "https://github.com/EnigmaCurry/d.rymcg.tech/";
          }
          {
            name = "blog.rymcg.tech";
            url = "https://blog.rymcg.tech/";
          }
          {
            name = "book.rymcg.tech";
            url = "https://book.rymcg.tech/";
          }
          {
            name = "nixos-vm-template";
            url = "https://github.com/EnigmaCurry/nixos-vm-template";
          }
          {
            name = "sway-home";
            url = "https://github.com/EnigmaCurry/sway-home/";
          }
        ];
      };

      extensions.packages = with firefox-addons; [
        ublock-origin
        darkreader
        vimium
        multi-account-containers
        temporary-containers
      ];

      search = {
        force = true;
        default = "ddg";
        privateDefault = "ddg";
        order = [ "ddg" ];
        engines = {
          "google".metaData.hidden = true;
          "bing".metaData.hidden = true;
          "amazondotcom-us".metaData.hidden = true;
          "ebay".metaData.hidden = true;
          "wikipedia".metaData.hidden = true;
          "perplexity".metaData.hidden = true;
          "ddg".metaData.alias = "@ddg";
        };
      };

      settings = {
        # Dark mode
        "layout.css.prefers-color-scheme.content-override" = 0;
        "browser.theme.content-theme" = 0;
        "browser.theme.toolbar-theme" = 0;
        "ui.systemUsesDarkTheme" = 1;
        "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";

        # Startup: restore previous session, blank new tab
        "browser.startup.homepage" = "about:blank";
        "browser.startup.page" = 3;
        "browser.newtabpage.enabled" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.feeds.section.highlights" = false;
        "browser.newtabpage.activity-stream.feeds.snippets" = false;
        "browser.newtabpage.activity-stream.default.sites" = "";

        # Disable telemetry
        "toolkit.telemetry.enabled" = false;
        "toolkit.telemetry.unified" = false;
        "toolkit.telemetry.server" = "";
        "toolkit.telemetry.archive.enabled" = false;
        "toolkit.telemetry.newProfilePing.enabled" = false;
        "toolkit.telemetry.shutdownPingSender.enabled" = false;
        "toolkit.telemetry.updatePing.enabled" = false;
        "toolkit.telemetry.bhrPing.enabled" = false;
        "toolkit.telemetry.firstShutdownPing.enabled" = false;
        "toolkit.telemetry.coverage.opt-out" = true;
        "toolkit.coverage.opt-out" = true;
        "toolkit.coverage.endpoint.base" = "";
        "datareporting.healthreport.uploadEnabled" = false;
        "datareporting.policy.dataSubmissionEnabled" = false;
        "app.shield.optoutstudies.enabled" = false;
        "app.normandy.enabled" = false;
        "app.normandy.api_url" = "";
        "browser.ping-centre.telemetry" = false;
        "breakpad.reportURL" = "";
        "browser.tabs.crashReporting.sendReport" = false;
        "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;

        # Disable Pocket and sponsored content
        "extensions.pocket.enabled" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;

        # Search suggestions
        "browser.search.suggest.enabled" = false;
        "browser.urlbar.suggest.searches" = false;
        "browser.urlbar.suggest.engines" = false;

        # History: clear on restart
        "privacy.sanitize.sanitizeOnShutdown" = true;
        "privacy.clearOnShutdown_v2.historyFormDataAndDownloads" = true;
        "privacy.clearOnShutdown_v2.cookiesAndStorage" = true;
        "privacy.clearOnShutdown_v2.cache" = true;
        "privacy.clearOnShutdown_v2.siteSettings" = false;
        "places.history.enabled" = false;

        # Privacy
        "browser.contentblocking.category" = "strict";
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;
        "privacy.trackingprotection.cryptomining.enabled" = true;
        "privacy.trackingprotection.fingerprinting.enabled" = true;
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        "signon.rememberSignons" = false;

        # HTTPS-only mode
        "dom.security.https_only_mode" = true;
        "dom.security.https_only_mode_ever_enabled" = true;

        # Extensions: auto-enable without user approval
        "extensions.autoDisableScopes" = 0;

        # Vertical tabs
        "sidebar.verticalTabs" = true;
        "sidebar.revamp" = true;

        # UI cleanup
        "browser.shell.checkDefaultBrowser" = false;
        "browser.aboutConfig.showWarning" = false;
        "browser.startup.homepage_override.mstone" = "ignore";
        "media.autoplay.default" = 5;
      };
    };
  };
}
