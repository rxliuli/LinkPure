#!/usr/bin/env node

/**
 * Download and convert external rule sources
 * Usage: node scripts/download_rules.js
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

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
  const exports = module.exports;
  const code = data.replace(/export\s+const\s+(\w+)\s*=/g, 'exports.$1 =');
  eval(code);

  return module.exports;
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
        id: `clearurls-${sanitizeID(providerName)}-redirect-${ruleID++}`,
        regexFilter: redirection,
        regexSubstitution: '$1'
      });
    });
  }

  // Convert raw rules
  if (provider.rawRules) {
    provider.rawRules.forEach((rawRule) => {
      rules.push({
        id: `clearurls-${sanitizeID(providerName)}-raw-${ruleID++}`,
        regexFilter: rawRule,
        regexSubstitution: ''
      });
    });
  }

  // Convert parameter rules
  if (provider.rules && provider.rules.length > 0) {
    rules.push({
      id: `clearurls-${sanitizeID(providerName)}-params`,
      regexFilter: provider.urlPattern,
      removeParams: provider.rules
    });
  }

  // Convert referral rules
  if (provider.referralMarketing && provider.referralMarketing.length > 0) {
    rules.push({
      id: `clearurls-${sanitizeID(providerName)}-referral`,
      regexFilter: provider.urlPattern,
      removeParams: provider.referralMarketing
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
      id = 'linkumori-global-params';
      regexFilter = '.*';
    } else {
      id = `linkumori-${sanitizeID(rule.domain)}-params`;
      const escaped = rule.domain.replace(/\./g, '\\.');
      regexFilter = `^https?:\\/\\/(?:[a-z0-9-]+\\.)*?${escaped}`;
    }

    // Filter out regex patterns in removeParams
    const cleanParams = rule.removeParams.filter(p => !p.startsWith('/'));

    if (cleanParams.length > 0) {
      rules.push({
        id,
        regexFilter,
        removeParams: cleanParams
      });
    }
  });

  return rules;
}

async function main() {
  try {
    const sourcesDir = path.join(__dirname, '../internal/rules/sources');

    // Ensure sources directory exists
    if (!fs.existsSync(sourcesDir)) {
      fs.mkdirSync(sourcesDir, { recursive: true });
    }

    // Download and convert ClearURLs
    console.log('Downloading ClearURLs rules...');
    const clearURLsData = await fetchJSON('https://rules2.clearurls.xyz/data.minify.json');
    const clearURLsRules = [];
    Object.entries(clearURLsData.providers).forEach(([name, provider]) => {
      clearURLsRules.push(...convertClearURLsProvider(name, provider));
    });

    const clearURLsOutput = {
      $schema: './schema.json',
      name: 'ClearURLs Rules',
      description: 'Rules imported from ClearURLs project',
      source: 'https://rules2.clearurls.xyz/data.minify.json',
      rules: clearURLsRules
    };

    fs.writeFileSync(
      path.join(sourcesDir, 'clearurls-rules.json'),
      JSON.stringify(clearURLsOutput, null, 2) + '\n',
      'utf8'
    );
    console.log(`✅ Saved ${clearURLsRules.length} ClearURLs rules to sources/clearurls-rules.json`);

    // Download and convert Linkumori
    console.log('\nDownloading Linkumori rules...');
    const linkumoriModule = await fetchJSModule(
      'https://raw.githubusercontent.com/Linkumori/Linkumori-Extension/fdea9e3677d963320cb0ccf2c1096b5534f4111b/common/rules.js'
    );
    const linkumoriRules = convertLinkumoriRules(linkumoriModule.parameterRules);

    const linkumoriOutput = {
      $schema: './schema.json',
      name: 'Linkumori Rules',
      description: 'Rules imported from Linkumori Extension',
      source: 'https://github.com/Linkumori/Linkumori-Extension',
      rules: linkumoriRules
    };

    fs.writeFileSync(
      path.join(sourcesDir, 'linkumori-rules.json'),
      JSON.stringify(linkumoriOutput, null, 2) + '\n',
      'utf8'
    );
    console.log(`✅ Saved ${linkumoriRules.length} Linkumori rules to sources/linkumori-rules.json`);

    // Create custom rules template if it doesn't exist
    const customRulesPath = path.join(sourcesDir, 'custom-rules.json');
    if (!fs.existsSync(customRulesPath)) {
      const customRulesTemplate = {
        $schema: './schema.json',
        name: 'Custom Rules',
        description: 'Manually maintained custom rules for link-pure',
        rules: []
      };
      fs.writeFileSync(
        customRulesPath,
        JSON.stringify(customRulesTemplate, null, 2) + '\n',
        'utf8'
      );
      console.log('\n✅ Created custom-rules.json template');
    }

    console.log('\n✨ Done! Run "node scripts/merge_sources.js" to merge all sources.');

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

main();
