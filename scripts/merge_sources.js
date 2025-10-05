#!/usr/bin/env node

/**
 * Merge all rule sources into shared-rules.json
 * Usage: node scripts/merge_sources.js
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadRuleSource(filePath) {
  try {
    const data = fs.readFileSync(filePath, 'utf8');
    const json = JSON.parse(data);
    return json.rules || [];
  } catch (e) {
    console.warn(`Warning: Could not load ${filePath}: ${e.message}`);
    return [];
  }
}

function mergeRules(ruleSets) {
  const ruleMap = new Map();
  const order = [];

  // Merge rules from all sets
  ruleSets.forEach(rules => {
    rules.forEach(rule => {
      if (!ruleMap.has(rule.id)) {
        ruleMap.set(rule.id, rule);
        order.push(rule.id);
      } else {
        // Rule exists, keep the first one (custom rules take precedence)
        console.log(`  ⚠️  Skipping duplicate rule: ${rule.id}`);
      }
    });
  });

  // Return rules in the order they were first seen
  return order.map(id => ruleMap.get(id));
}

function main() {
  const sourcesDir = path.join(__dirname, '../internal/rules/sources');
  const outputPath = path.join(__dirname, '../internal/rules/assets/shared-rules.json');

  console.log('Loading rule sources...\n');

  // Load rules in priority order (first = highest priority)
  const sources = [
    { name: 'Custom Rules', file: 'custom-rules.json' },
    { name: 'Linkumori', file: 'linkumori-rules.json' },
    { name: 'ClearURLs', file: 'clearurls-rules.json' }
  ];

  const ruleSets = [];
  const stats = [];

  sources.forEach(({ name, file }) => {
    const filePath = path.join(sourcesDir, file);
    const rules = loadRuleSource(filePath);
    if (rules.length > 0) {
      ruleSets.push(rules);
      stats.push({ name, count: rules.length });
      console.log(`  ✅ ${name}: ${rules.length} rules`);
    } else {
      console.log(`  ⚠️  ${name}: 0 rules`);
    }
  });

  console.log('\nMerging rules...');
  const mergedRules = mergeRules(ruleSets);

  const output = {
    $schema: './schema.json',
    name: 'Shared Rules',
    description: 'Combined tracking parameter cleaning and redirect unwrapping rules',
    rules: mergedRules
  };

  fs.writeFileSync(outputPath, JSON.stringify(output, null, 2) + '\n', 'utf8');

  console.log(`\n✅ Successfully merged ${mergedRules.length} rules to ${path.relative(process.cwd(), outputPath)}`);
  console.log('\nBreakdown:');
  stats.forEach(({ name, count }) => {
    console.log(`  - ${name}: ${count} rules`);
  });

  const duplicates = stats.reduce((sum, s) => sum + s.count, 0) - mergedRules.length;
  if (duplicates > 0) {
    console.log(`  - Duplicates removed: ${duplicates}`);
  }
}

main();
