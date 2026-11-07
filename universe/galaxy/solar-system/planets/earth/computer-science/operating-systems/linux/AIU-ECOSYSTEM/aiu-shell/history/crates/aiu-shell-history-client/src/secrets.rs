// This file will probably trigger a lot of scanners. Sorry.

use regex::RegexSet;
use std::sync::LazyLock;

pub enum TestValue<'a> {
    Single(&'a str),
    Multiple(&'a [&'a str]),
}

/// A list of `(name, regex, test)`, where `test` should match against `regex`.
pub static SECRET_PATTERNS: &[(&str, &str, TestValue)] = &[
    (
        "AWS Access Key ID",
        "A[KS]IA[0-9A-Z]{16}",
        TestValue::Single("AKIAIOSFODNN7EXAMPLE"),
    ),
    (
        "AWS Secret Access Key env var",
        "AWS_SECRET_ACCESS_KEY",
        TestValue::Single("AWS_SECRET_ACCESS_KEY=KEYDATA"),
    ),
    (
        "AWS Session Token env var",
        "AWS_SESSION_TOKEN",
        TestValue::Single("AWS_SESSION_TOKEN=KEYDATA"),
    ),
    (
        "Microsoft Azure secret access key env var",
        "AZURE_.*_KEY",
        TestValue::Single("export AZURE_STORAGE_ACCOUNT_KEY=KEYDATA"),
    ),
    (
        "Google cloud platform key env var",
        "GOOGLE_SERVICE_ACCOUNT_KEY",
        TestValue::Single("export GOOGLE_SERVICE_ACCOUNT_KEY=KEYDATA"),
    ),
    (
        "aiu-shell-history login",
        r"aiu-shell-history\s+login",
        TestValue::Single(
            "aiu-shell-history login -u mycoolusername -p mycoolpassword -k \"lots of random words\"",
        ),
    ),
    (
        "GitHub PAT (old)",
        "ghp_[a-zA-Z0-9]{36}",
        TestValue::Single(concat!("ghp_", "000000000000000000000000000000000000")), // fake sample
    ),
    (
        "GitHub PAT (new)",
        "gh1_[A-Za-z0-9]{21}_[A-Za-z0-9]{59}|github_pat_[0-9][A-Za-z0-9]{21}_[A-Za-z0-9]{59}",
        TestValue::Multiple(&[
            "gh1_1234567890abcdefghijk_1234567890abcdefghijklmnopqrstuvwxyz1234567890abcdefghijklm",
            concat!("github_pat_", "0000000000000000000000", "_", "00000000000000000000000000000000000000000000000000000000000"), // also legit, also expired
        ]),
    ),
    (
        "GitHub OAuth Access Token",
        "gho_[A-Za-z0-9]{36}",
        TestValue::Single(concat!("gho_", "1234567890abcdefghijklmnopqrstuvwx000")), // not a real token
    ),
    (
        "GitHub OAuth Access Token (user)",
        "ghu_[A-Za-z0-9]{36}",
        TestValue::Single(concat!("ghu_", "1234567890abcdefghijklmnopqrstuvwx000")), // not a real token
    ),
    (
        "GitHub App Installation Access Token",
        "ghs_[A-Za-z0-9._-]{36,}",
        TestValue::Multiple(&[
            concat!("ghs_", "1234567890abcdefghijklmnopqrstuvwx000"), // not a real token
            concat!("ghs_", "abc-def.ghi_jklMNOP0123456789qrstuv-wxyzABCD"), // new token format, fake data
        ]),
    ),
    (
        "GitHub Refresh Token",
        "ghr_[A-Za-z0-9]{76}",
        TestValue::Single(
            concat!("ghr_", "0000000000000000000000000000000000000000000000000000000000000000000000000000"),
        ), // not a real token
    ),
    (
        "GitHub App Installation Access Token v1",
        "v1\\.[0-9A-Fa-f]{40}",
        TestValue::Single(concat!("v1.", "0000000000000000000000000000000000000000")), // not a real token
    ),
    (
        "GitLab PAT",
        "glpat-[a-zA-Z0-9_]{20}",
        TestValue::Single(concat!("glpat-", "00000000000000000000")),
    ),
    (
        "Slack OAuth v2 bot",
        "xoxb-[0-9]{11}-[0-9]{11}-[0-9a-zA-Z]{24}",
        TestValue::Single(concat!("xoxb-", "00000000000", "-", "00000000000", "-", "000000000000000000000000")),
    ),
    (
        "Slack OAuth v2 user token",
        "xoxp-[0-9]{11}-[0-9]{11}-[0-9a-zA-Z]{24}",
        TestValue::Single(concat!("xoxp-", "00000000000", "-", "00000000000", "-", "000000000000000000000000")),
    ),
    (
        "Slack webhook",
        "T[a-zA-Z0-9_]{8}/B[a-zA-Z0-9_]{8}/[a-zA-Z0-9_]{24}",
        TestValue::Single(
            concat!("https://hooks.slack.", "com/services/T00000000/", "B00000000/", "XXXXXXXXXXXXXXXXXXXXXXXX"),
        ),
    ),
    (
        "Stripe test key",
        "sk_test_[0-9a-zA-Z]{24}",
        TestValue::Single(concat!("sk_test_", "1234567890abcdefghijklmnop")),
    ),
    (
        "Stripe live key",
        "sk_live_[0-9a-zA-Z]{24}",
        TestValue::Single(concat!("sk_live_", "1234567890abcdefghijklmnop")),
    ),
    (
        "Netlify authentication token",
        "nf[pcoub]_[0-9a-zA-Z]{36}",
        TestValue::Single(concat!("nfp_", "000000000000000000000000000000000000")),
    ),
    (
        "npm token",
        "npm_[A-Za-z0-9]{36}",
        TestValue::Single(concat!("npm_", "000000000000000000000000000000000000")),
    ),
    (
        "Pulumi personal access token",
        "pul-[0-9a-f]{40}",
        TestValue::Single(concat!("pul-", "0000000000000000000000000000000000000000")),
    ),
];

/// The `regex` expressions from [`SECRET_PATTERNS`] compiled into a `RegexSet`.
pub static SECRET_PATTERNS_RE: LazyLock<RegexSet> = LazyLock::new(|| {
    let exprs = SECRET_PATTERNS.iter().map(|f| f.1);
    RegexSet::new(exprs).expect("Failed to build secrets regex")
});

#[cfg(test)]
mod tests {
    use regex::Regex;

    use crate::secrets::{SECRET_PATTERNS, TestValue};

    #[test]
    fn test_secrets() {
        for (name, regex, test) in SECRET_PATTERNS {
            let re =
                Regex::new(regex).unwrap_or_else(|_| panic!("Failed to compile regex for {name}"));

            match test {
                TestValue::Single(test) => {
                    assert!(re.is_match(test), "{name} test failed!");
                }
                TestValue::Multiple(tests) => {
                    for test_str in tests.iter() {
                        assert!(
                            re.is_match(test_str),
                            "{name} test with value \"{test_str}\" failed!"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn test_secrets_embedded() {
        for (name, regex, test) in SECRET_PATTERNS {
            let re =
                Regex::new(regex).unwrap_or_else(|_| panic!("Failed to compile regex for {name}"));

            match test {
                TestValue::Single(test) => {
                    let embedded = format!("some random text {test} some more random text");
                    assert!(re.is_match(&embedded), "{name} embedded test failed!");
                }
                TestValue::Multiple(tests) => {
                    for test_str in tests.iter() {
                        let embedded = format!("some random text {test_str} some more random text");
                        assert!(
                            re.is_match(&embedded),
                            "{name} embedded test with value \"{test_str}\" failed!"
                        );
                    }
                }
            }
        }
    }
}
