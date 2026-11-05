import GzymsCore
import Testing

@Test func reportConfigHidesSecretsAndNames() {
    let toml = """
    theme = "mocha"
    [notifications.phone]
    url = "https://ntfy.sh/secret-topic"
    pushover_user = "u123"
    pushover_token = "t456"
    format = "short"
    [calendar]
    skip = [
      "Anna's birthdays",
      "Work",
    ]
    [plugins.log-watcher]
    files = ["/Users/greg/app.log"]
    """
    let out = ReportScrub.config(toml)
    for leak in ["secret-topic", "u123", "t456", "Anna", "Work", "app.log"] { #expect(!out.contains(leak)) }
    #expect(out.contains("theme = \"mocha\""))
    #expect(out.contains("format = \"short\""))
    #expect(out.contains("pushover_token = \"<hidden>\""))
    #expect(out.contains("[plugins.log-watcher]"))
}

@Test func reportTextDropsHomeAndSites() {
    let log = "T1 permissions: /Users/greg/Applications/Gzyms.app\nT2 media: jbzd.com.pl: focus (highlight): ok\nT3 media: userscript server on 127.0.0.1:47100"
    let out = ReportScrub.text(log, home: "/Users/greg")
    #expect(out == "T1 permissions: ~/Applications/Gzyms.app\nT2 media: <site>: focus (highlight): ok\nT3 media: userscript server on 127.0.0.1:47100")
}
