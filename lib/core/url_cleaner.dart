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

  MatchResult check(String url) {
    if (!isValidUrl(url)) {
      return MatchResult(status: CheckStatus.notMatched, url: url, chain: []);
    }
    String currentUrl = url;
    List<String> chain = [];
    int maxRedirects = 5;

    for (int i = 0; i < maxRedirects; i++) {
      bool matched = false;
      for (var rule in rules) {
        String newUrl = matchWithRule(rule, currentUrl);
        if (newUrl.isNotEmpty && newUrl != currentUrl) {
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

  static String matchWithRule(Rule rule, String url) {
    final RegExp regex;
    try {
      regex = RegExp(rule.regexFilter);
    } catch (e) {
      return "";
    }
    if (!regex.hasMatch(url)) {
      return "";
    }
    return applyRule(rule, url);
  }

  static String applyRule(Rule rule, String url) {
    if (rule.regexSubstitution != null && rule.regexSubstitution!.isNotEmpty) {
      return applyRegexSubstitution(rule, url);
    }
    if (rule.removeParams != null && rule.removeParams!.isNotEmpty) {
      return removeQueryParameters(url, rule.removeParams!);
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
}
