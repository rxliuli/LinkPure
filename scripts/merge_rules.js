#!/usr/bin/env node

/**
 * Merge URL cleaning rules from external sources (Legacy - use download_rules.js + merge_sources.js instead)
 * Usage: node scripts/merge_rules.js
 */

import { readFileSync, writeFileSync } from 'fs';
import { join, relative } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));

// Download JSON data
async function fetchJSON(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  return await response.json();
}

// Download JavaScript module and evaluate it
async function fetchJSModule(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status}`);
  }
  const data = await response.text();

  const module = { exports: {} };
  const code = data.replace(/export\s+const\s+(\w+)\s*=/g, 'module.exports.$1 =');
  eval(code);

  return module.exports;
}

// Load existing rules
function loadExistingRules() {
  const rulesPath = join(__dirname, '../internal/rules/assets/shared-rules.json');
  try {
    const data = readFileSync(rulesPath, 'utf8');
    return JSON.parse(data).rules || [];
  } catch (e) {
    if (e.code === 'ENOENT') {
      return [];
    }
    throw e;
  }
}

// Convert ClearURLs provider to our format
function convertClearURLsProvider(providerName, provider) {
  const rules = [];
  let ruleID = 0;

  const sanitizeID = (s) => s.toLowerCase().replace(/[^a-z0-9-.]/g, '');

  // Convert redirections
  if (provider.redirections) {
    provider.redirections.forEach((redirection) => {
      rules.push({
        id: `${sanitizeID(providerName)}-redirect-${ruleID++}`,
        regexFilter: redirection,
        regexSubstitution: '$1',
      });
    });
  }

  // Convert raw rules (URL path cleaning)
  if (provider.rawRules) {
    provider.rawRules.forEach((rawRule) => {
      rules.push({
        id: `${sanitizeID(providerName)}-raw-${ruleID++}`,
        regexFilter: rawRule,
        regexSubstitution: '',
      });
    });
  }

  // Convert parameter rules
  if (provider.rules && provider.rules.length > 0) {
    rules.push({
      id: `${sanitizeID(providerName)}-params`,
      regexFilter: provider.urlPattern,
      removeParams: provider.rules,
    });
  }

  // Convert referral rules
  if (provider.referralMarketing && provider.referralMarketing.length > 0) {
    rules.push({
      id: `${sanitizeID(providerName)}-referral`,
      regexFilter: provider.urlPattern,
      removeParams: provider.referralMarketing,
    });
  }

  return rules;
}

// Convert Linkumori parameterRules to our format
function convertLinkumoriRules(parameterRules) {
  const rules = [];
  const sanitizeID = (s) => s.toLowerCase().replace(/[^a-z0-9-.]/g, '');

  parameterRules.forEach((rule) => {
    let id, regexFilter;

    if (!rule.domain) {
      // Global rules
      id = 'linkumori-global-params';
      regexFilter = '.*';
    } else {
      // Domain-specific rules
      id = `linkumori-${sanitizeID(rule.domain)}-params`;
      // Convert domain to regex pattern
      const escaped = rule.domain.replace(/\./g, '\\.');
      regexFilter = `^https?:\\/\\/(?:[a-z0-9-]+\\.)*?${escaped}`;
    }

    // Filter out regex patterns in removeParams (they start with /)
    const cleanParams = rule.removeParams.filter((p) => !p.startsWith('/'));

    if (cleanParams.length > 0) {
      rules.push({
        id,
        regexFilter,
        removeParams: cleanParams,
      });
    }
  });

  return rules;
}

// Merge rules, keeping existing ones with same ID
function mergeRules(newRules, existingRules) {
  const ruleMap = new Map();

  // Add existing rules first (they take precedence)
  existingRules.forEach((rule) => ruleMap.set(rule.id, rule));

  // Add new rules only if ID doesn't exist
  newRules.forEach((rule) => {
    if (!ruleMap.has(rule.id)) {
      ruleMap.set(rule.id, rule);
    }
  });

  return Array.from(ruleMap.values());
}

// Main function
async function main() {
  try {
    console.log('Loading existing rules...');
    const existingRules = loadExistingRules();
    console.log(`  Found ${existingRules.length} existing rules`);

    console.log('\nDownloading ClearURLs rules...');
    const clearURLsData = await fetchJSON('https://rules2.clearurls.xyz/data.minify.json');
    const clearURLsRules = [];
    Object.entries(clearURLsData.providers).forEach(([name, provider]) => {
      clearURLsRules.push(...convertClearURLsProvider(name, provider));
    });
    console.log(`  Converted ${clearURLsRules.length} ClearURLs rules`);

    console.log('\nDownloading Linkumori rules...');
    const linkumoriModule = await fetchJSModule(
      'https://raw.githubusercontent.com/Linkumori/Linkumori-Extension/fdea9e3677d963320cb0ccf2c1096b5534f4111b/common/rules.js',
    );
    const linkumoriRules = convertLinkumoriRules(linkumoriModule.parameterRules);
    console.log(`  Converted ${linkumoriRules.length} Linkumori rules`);

    console.log('\nMerging rules...');
    const allNewRules = [...clearURLsRules, ...linkumoriRules];
    const mergedRules = mergeRules(allNewRules, existingRules);

    const output = {
      $schema: './schema.json',
      name: 'Shared Rules',
      description: 'Combined tracking parameter cleaning and redirect unwrapping rules',
      rules: mergedRules,
    };

    const outputPath = join(__dirname, '../internal/rules/assets/shared-rules.json');
    writeFileSync(outputPath, JSON.stringify(output, null, 2) + '\n', 'utf8');

    console.log(
      `\n✅ Successfully merged ${mergedRules.length} rules to ${relative(process.cwd(), outputPath)}`,
    );
    console.log(`  - Existing rules: ${existingRules.length}`);
    console.log(`  - New rules: ${mergedRules.length - existingRules.length}`);
    console.log(`    - From ClearURLs: ${clearURLsRules.length}`);
    console.log(`    - From Linkumori: ${linkumoriRules.length}`);
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
