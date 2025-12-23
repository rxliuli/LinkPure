import 'package:http/http.dart' as http;
import '../models/rule.dart';

enum CheckStatus { matched, notMatched, circularRedirect, infiniteRedirect }

class MatchResult {
  final CheckStatus status;
  final String url;
  final List<String> chain;
  MatchResult({required this.status, required this.url, required this.chain});
}

class UrlCleaner {
  final List<Rule> rules;
  UrlCleaner({required this.rules});

  Future<MatchResult> check(String url) async {
    if (!isValidUrl(url)) {
      return MatchResult(status: CheckStatus.notMatched, url: url, chain: []);
    }
    String currentUrl = url;
    List<String> chain = [];
    int maxRedirects = 5;

    for (int i = 0; i < maxRedirects; i++) {
      bool matched = false;
      for (var rule in rules) {
        String? newUrl = await matchWithRule(rule, currentUrl);
        if (newUrl != null && newUrl.isNotEmpty && newUrl != currentUrl) {
          if (chain.contains(newUrl)) {
            return MatchResult(
              status: CheckStatus.circularRedirect,
              url: newUrl,
              chain: chain,
            );
          }
          chain.add(newUrl);
          currentUrl = newUrl;
          matched = true;
          break;
        }
      }
      if (!matched) {
        return MatchResult(
          status: chain.isEmpty ? CheckStatus.notMatched : CheckStatus.matched,
          url: chain.isEmpty ? "" : currentUrl,
          chain: chain,
        );
      }
    }
    return MatchResult(
      status: CheckStatus.infiniteRedirect,
      url: currentUrl,
      chain: chain,
    );
  }

  static Future<String?> matchWithRule(Rule rule, String url) async {
    final RegExp regex;
    try {
      regex = RegExp(rule.regexFilter);
    } catch (e) {
      return null;
    }
    if (!regex.hasMatch(url)) {
      return null;
    }
    return await applyRule(rule, url);
  }

  static Future<String?> applyRule(Rule rule, String url) async {
    if (rule.regexSubstitution != null && rule.regexSubstitution!.isNotEmpty) {
      return applyRegexSubstitution(rule, url);
    }
    if (rule.removeParams != null && rule.removeParams!.isNotEmpty) {
      return removeQueryParameters(url, rule.removeParams!);
    }
    if (rule.followRedirect == true) {
      return await followRedirectUrl(url);
    }
    return url;
  }

  static String applyRegexSubstitution(Rule rule, String url) {
    final RegExp regex;
    try {
      regex = RegExp(rule.regexFilter);
    } catch (e) {
      return url;
    }

    final match = regex.firstMatch(url);
    if (match == null) {
      return url;
    }

    String result = rule.regexSubstitution!;

    for (int i = 1; i <= match.groupCount; i++) {
      final capturedValue = match.group(i) ?? '';

      String decodedValue;
      try {
        decodedValue = Uri.decodeComponent(capturedValue);
      } catch (e) {
        decodedValue = capturedValue;
      }

      final placeholder = '\$$i';
      result = result.replaceAll(placeholder, decodedValue);
    }

    return result;
  }

  static String removeQueryParameters(String url, List<String> paramsToRemove) {
    Uri uri = Uri.parse(url);

    // Create a mutable copy of query parameters
    Map<String, String> params = Map.from(uri.queryParameters);
    int originalParamCount = params.length;
    
    params.removeWhere((param, value) {
      for (var pattern in paramsToRemove) {
        if (containsAny(pattern, "^\$()[]{}*+?|\\")) {
          // Try to use as regex pattern
          try {
            if (RegExp(pattern).hasMatch(param)) {
              return true;
            }
          } catch (e) {
            // If pattern is invalid regex, ignore it and continue
            continue;
          }
        } else {
          // Exact match for non-regex patterns
          if (param == pattern) {
            return true;
          }
        }
      }
      return false;
    });

    // If no parameters were removed, return the original URL unchanged
    if (params.length == originalParamCount) {
      return url;
    }

    // Rebuild the URI with the filtered parameters
    final result = uri.replace(queryParameters: params).toString();
    // Remove trailing '?' if all parameters were removed
    return result.endsWith('?')
        ? result.substring(0, result.length - 1)
        : result;
  }

  static bool isValidUrl(String text) {
    try {
      final uri = Uri.parse(text);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  static bool containsAny(String text, String patternString) {
    List<String> patterns = patternString.split('');
    for (var pattern in patterns) {
      if (text.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  static Future<String?> followRedirectUrl(String url) async {
    try {
      var currentUri = Uri.parse(url);
      var redirectCount = 0;
      const maxRedirects = 10;

      final client = http.Client();
      try {
        while (redirectCount < maxRedirects) {
          final request = http.Request('GET', currentUri)
            ..followRedirects = false;
          final streamedResponse = await client.send(request).timeout(
            const Duration(seconds: 5),
          );

          // Check if this is a redirect response
          if (streamedResponse.statusCode >= 300 && streamedResponse.statusCode < 400) {
            final location = streamedResponse.headers['location'];
            if (location == null) {
              // No location header, return current URL
              return currentUri.toString();
            }

            // Parse the new location (might be relative or absolute)
            final newUri = Uri.parse(location);
            currentUri = newUri.hasScheme ? newUri : currentUri.resolve(location);
            redirectCount++;
          } else {
            // Not a redirect, return the current URL
            return currentUri.toString();
          }
        }

        // Hit max redirects
        return currentUri.toString();
      } finally {
        client.close();
      }
    } catch (e) {
      // If any error occurs (network, timeout, etc.), treat as rule not matched
      return null;
    }
  }
}
