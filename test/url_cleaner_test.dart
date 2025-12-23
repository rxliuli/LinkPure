import 'package:flutter_test/flutter_test.dart';
import 'package:link_pure/core/url_cleaner.dart';
import 'package:link_pure/models/rule.dart';

void main() {
  group('UrlCleaner.isValidUrl', () {
    test('returns true for valid HTTP URLs', () {
      expect(UrlCleaner.isValidUrl('http://example.com'), true);
      expect(UrlCleaner.isValidUrl('http://example.com/path'), true);
    });

    test('returns true for valid HTTPS URLs', () {
      expect(UrlCleaner.isValidUrl('https://example.com'), true);
      expect(
        UrlCleaner.isValidUrl('https://example.com/path?query=value'),
        true,
      );
    });

    test('returns false for invalid URLs', () {
      expect(UrlCleaner.isValidUrl('not a url'), false);
      expect(UrlCleaner.isValidUrl('ftp://example.com'), false);
      expect(UrlCleaner.isValidUrl(''), false);
    });
  });

  group('UrlCleaner.applyRegexSubstitution', () {
    test('replaces captured groups with decoded values', () {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com/redirect\?url=([^&]+)',
        regexSubstitution: r'$1',
      );
      final url = 'https://example.com/redirect?url=https%3A%2F%2Ftarget.com';
      final result = UrlCleaner.applyRegexSubstitution(rule, url);
      expect(result, 'https://target.com');
    });

    test('handles multiple captured groups', () {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com/(\w+)/(\w+)',
        regexSubstitution: r'https://newsite.com/$2/$1',
      );
      final url = 'https://example.com/foo/bar';
      final result = UrlCleaner.applyRegexSubstitution(rule, url);
      expect(result, 'https://newsite.com/bar/foo');
    });

    test('returns original URL if regex does not match', () {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com/path',
        regexSubstitution: r'https://newsite.com',
      );
      final url = 'https://different.com/path';
      final result = UrlCleaner.applyRegexSubstitution(rule, url);
      expect(result, url);
    });

    test('handles decoding errors gracefully', () {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com/redirect\?url=([^&]+)',
        regexSubstitution: r'$1',
      );
      final url = 'https://example.com/redirect?url=invalid%';
      final result = UrlCleaner.applyRegexSubstitution(rule, url);
      expect(result, 'invalid%');
    });
  });

  group('UrlCleaner.removeQueryParameters', () {
    test('removes exact matching parameters', () {
      final url = 'https://example.com?foo=1&bar=2&baz=3';
      final result = UrlCleaner.removeQueryParameters(url, ['bar']);
      expect(result, 'https://example.com?foo=1&baz=3');
    });

    test('removes multiple parameters', () {
      final url = 'https://example.com?foo=1&bar=2&baz=3';
      final result = UrlCleaner.removeQueryParameters(url, ['foo', 'baz']);
      expect(result, 'https://example.com?bar=2');
    });

    test('handles regex patterns in parameter names', () {
      final url =
          'https://example.com?utm_source=test&utm_medium=email&foo=bar';
      final result = UrlCleaner.removeQueryParameters(url, [r'utm_.*']);
      expect(result, 'https://example.com?foo=bar');
    });

    test('returns URL unchanged if no parameters match', () {
      final url = 'https://example.com?foo=1&bar=2';
      final result = UrlCleaner.removeQueryParameters(url, ['baz']);
      expect(result, url);
    });
  });

  group('UrlCleaner.followRedirectUrl', () {
    test('follows HTTP redirects and returns final URL', () async {
      // This test requires a real URL that performs a redirect.
      // For demonstration purposes, we'll use httpbin.org.
      final url = 'http://httpbin.org/redirect/1';
      final result = await UrlCleaner.followRedirectUrl(url);
      expect(result, 'http://httpbin.org/get');
    });
    test('handles Twitter t.co redirects', () async {
      final url = 'https://t.co/UQrtAuVhHI';
      final result = await UrlCleaner.followRedirectUrl(url);
      expect(result, 'https://rxliuli.com/');
    });
    test('returns original URL if no redirects occur', () async {
      final url = 'https://example.com';
      final result = await UrlCleaner.followRedirectUrl(url);
      expect(result, url);
    });
  });

  group('UrlCleaner.matchWithRule', () {
    test('applies regex substitution rule', () async {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com/redirect\?url=([^&]+)',
        regexSubstitution: r'$1',
      );
      final url = 'https://example.com/redirect?url=https%3A%2F%2Ftarget.com';
      final result = await UrlCleaner.matchWithRule(rule, url);
      expect(result, 'https://target.com');
    });

    test('applies removeParams rule', () async {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com',
        removeParams: ['utm_source', 'utm_medium'],
      );
      final url = 'https://example.com?utm_source=test&foo=bar';
      final result = await UrlCleaner.matchWithRule(rule, url);
      expect(result, 'https://example.com?foo=bar');
    });

    test('returns null if regex does not match', () async {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com',
        regexSubstitution: r'https://newsite.com',
      );
      final url = 'https://different.com';
      final result = await UrlCleaner.matchWithRule(rule, url);
      expect(result, null);
    });
  });

  group('UrlCleaner.check', () {
    test('returns notMatched for invalid URLs', () async {
      final cleaner = UrlCleaner(rules: []);
      final result = await cleaner.check('not a url');
      expect(result.status, CheckStatus.notMatched);
      expect(result.url, 'not a url');
    });

    test('applies single rule successfully', () async {
      final rule = Rule(
        id: 'test',
        regexFilter: r'https://example\.com',
        removeParams: ['utm_source'],
      );
      final cleaner = UrlCleaner(rules: [rule]);
      final result = await cleaner.check(
        'https://example.com?utm_source=test&foo=bar',
      );
      expect(result.status, CheckStatus.matched);
      expect(result.url, 'https://example.com?foo=bar');
    });

    test('applies multiple rules in sequence', () async {
      final rule1 = Rule(
        id: 'test1',
        regexFilter: r'https://redirect\.com\?url=([^&]+)',
        regexSubstitution: r'$1',
      );
      final rule2 = Rule(
        id: 'test2',
        regexFilter: r'https://target\.com',
        removeParams: ['tracking'],
      );
      final cleaner = UrlCleaner(rules: [rule1, rule2]);
      final result = await cleaner.check(
        'https://redirect.com?url=https%3A%2F%2Ftarget.com%3Ftracking%3D123%26foo%3Dbar',
      );
      expect(result.status, CheckStatus.matched);
      expect(result.chain.length, 2);
    });

    test('detects circular redirects', () async {
      final rule1 = Rule(
        id: 'test1',
        regexFilter: r'https://site1\.com',
        regexSubstitution: r'https://site2.com',
      );
      final rule2 = Rule(
        id: 'test2',
        regexFilter: r'https://site2\.com',
        regexSubstitution: r'https://site1.com',
      );
      final cleaner = UrlCleaner(rules: [rule1, rule2]);
      final result = await cleaner.check('https://site1.com');
      expect(result.status, CheckStatus.circularRedirect);
    });
  });

  group('UrlCleaner.containsAny', () {
    test('returns true if text contains any pattern character', () {
      expect(UrlCleaner.containsAny('hello[world', '[]'), true);
      expect(UrlCleaner.containsAny('test*value', '*+'), true);
    });

    test('returns false if text contains no pattern characters', () {
      expect(UrlCleaner.containsAny('hello', '[]'), false);
      expect(UrlCleaner.containsAny('test', '*+'), false);
    });
  });

  group("Real Tests", () {
    test("clean twitter share link", () async {
      final cleaner = UrlCleaner(
        rules: List.from([
          Rule(
            id: 'clearurls-twitter-params',
            regexFilter: "^https?:\\/\\/(?:[a-z0-9-]+\\.)*?x.com",
            removeParams: [r'(?:ref_?)?src', 's', 'cn', 'ref_url', 't'],
          ),
        ]),
      );
      final inputUrl =
          "https://x.com/viditchess/status/1992583484259643817?s=20";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.matched);
      expect(result.url, "https://x.com/viditchess/status/1992583484259643817");
    });
    test("should not clean non-share link", () async {
      final cleaner = UrlCleaner(
        rules: List.from([
          Rule(
            id: 'clearurls-twitter-params',
            regexFilter: "^https?:\\/\\/(?:[a-z0-9-]+\\.)*?youtu\\.be",
            removeParams: ["si"],
          ),
        ]),
      );
      final inputUrl = "https://youtu.be/(.*)\\?";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.notMatched);
      expect(result.url, "");
    });
    test("follow t.co redirect", () async {
      final cleaner = UrlCleaner(
        rules: List.from([
          Rule(
            id: 'clearurls-twitter-params',
            regexFilter: "^https://t\\.co/\\w+\$",
            followRedirect: true,
          ),
        ]),
      );
      final inputUrl = "https://t.co/UQrtAuVhHI";
      final result = await cleaner.check(inputUrl);
      expect(result.status, CheckStatus.matched);
      expect(result.url, "https://rxliuli.com/");
    });
  });
}
