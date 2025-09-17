#!/usr/bin/env python3

import json
import re
import matplotlib.pyplot as plt
import pandas as pd
from datetime import datetime
import os
import sys
from pathlib import Path

def fix_json_file(filepath):
    """Fix common JSON formatting issues in Thanos results"""
    print(f"Reading file: {filepath}")
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    print(f"Original file size: {len(content):,} characters")
    
    # Fix common JSON issues
    # Remove double commas
    content = re.sub(r',\s*,', ',', content)
    # Remove trailing commas before closing braces
    content = re.sub(r',\s*\}\}$', '}}', content)
    content = re.sub(r',\s*\}', '}', content)
    
    try:
        data = json.loads(content)
        print("JSON is now valid!")
        return data
    except json.JSONDecodeError as e:
        print(f"JSON still invalid: {e}")
        return None

def extract_time_series_data(metric_data):
    """Extract time series data from Prometheus metric result"""
    if not isinstance(metric_data, dict) or metric_data.get('status') != 'success':
        return []
    
    result = metric_data.get('data', {}).get('result', [])
    all_series = []
    
    for series in result:
        metric_labels = series.get('metric', {})
        values = series.get('values', [])
        
        # Convert to pandas-friendly format
        timestamps = []
        metric_values = []
        
        for timestamp, value in values:
            try:
                timestamps.append(datetime.fromtimestamp(int(timestamp)))
                metric_values.append(float(value))
            except (ValueError, TypeError):
                continue
        
        if timestamps and metric_values:
            series_data = {
                'timestamps': timestamps,
                'values': metric_values,
                'labels': metric_labels
            }
            all_series.append(series_data)
    
    return all_series

def create_metric_plot(metric_name, series_data, output_dir):
    """Create a plot for a single metric with all its time series"""
    if not series_data:
        print(f"No data for metric: {metric_name}")
        return
    
    plt.figure(figsize=(12, 8))
    
    # Plot each time series
    for i, series in enumerate(series_data):
        timestamps = series['timestamps']
        values = series['values']
        labels = series['labels']
        
        # Create a label for the legend
        label_parts = []
        for key, value in labels.items():
            if key not in ['__name__', 'prometheus', 'job'] and len(str(value)) < 20:
                label_parts.append(f"{key}={value}")
        
        legend_label = ', '.join(label_parts[:3])  # Limit to first 3 labels
        if len(label_parts) > 3:
            legend_label += "..."
        
        plt.plot(timestamps, values, label=legend_label, marker='o', markersize=2, linewidth=1)
    
    plt.title(f"Metric: {metric_name}", fontsize=14, fontweight='bold')
    plt.xlabel("Time", fontsize=12)
    plt.ylabel("Value", fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.xticks(rotation=45)
    
    # Add legend if not too many series
    if len(series_data) <= 10:
        plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
    
    plt.tight_layout()
    
    # Save plot
    safe_name = re.sub(r'[^a-zA-Z0-9_-]', '_', metric_name)
    plot_path = os.path.join(output_dir, f"plot_{safe_name}.png")
    plt.savefig(plot_path, dpi=150, bbox_inches='tight')
    plt.close()
    
    print(f"Created plot: {plot_path}")

def analyze_metrics_file(filepath, output_dir="plots"):
    """Analyze Thanos metrics file and create individual plots"""
    
    print("=" * 60)
    print("THANOS METRICS ANALYSIS & PLOTTING")
    print("=" * 60)
    
    # Create output directory
    Path(output_dir).mkdir(exist_ok=True)
    
    # Fix and load JSON
    data = fix_json_file(filepath)
    if not data:
        return
    
    # Extract metadata
    benchmark_start = data.get('benchmark_start', 'Unknown')
    benchmark_end = data.get('benchmark_end', 'Unknown')
    available_vllm = data.get('available_vllm_metrics', '')
    
    print(f"Benchmark period: {benchmark_start} to {benchmark_end}")
    print(f"Available vLLM metrics: {len(available_vllm.split()) if available_vllm else 0}")
    
    # Analyze metrics
    metrics = data.get('metrics', {})
    print(f"Total metrics collected: {len(metrics)}")
    
    successful_metrics = []
    failed_metrics = []
    empty_metrics = []
    
    for metric_name, metric_data in metrics.items():
        if isinstance(metric_data, dict):
            if metric_data.get('status') == 'success':
                result_data = metric_data.get('data', {}).get('result', [])
                if result_data:
                    successful_metrics.append(metric_name)
                else:
                    empty_metrics.append(metric_name)
            else:
                failed_metrics.append(metric_name)
    
    print(f"Successful metrics: {len(successful_metrics)}")
    print(f"Failed metrics: {len(failed_metrics)}")
    print(f"Empty metrics: {len(empty_metrics)}")
    print()
    
    # Create plots for successful metrics
    print("Creating individual plots...")
    plot_count = 0
    
    for metric_name in successful_metrics:
        try:
            series_data = extract_time_series_data(metrics[metric_name])
            if series_data:
                create_metric_plot(metric_name, series_data, output_dir)
                plot_count += 1
        except Exception as e:
            print(f"Error plotting {metric_name}: {e}")
    
    print(f"Created {plot_count} plots in '{output_dir}/' directory")
    
    # Create summary report
    summary_path = os.path.join(output_dir, "analysis_summary.txt")
    with open(summary_path, 'w') as f:
        f.write(f"THANOS METRICS ANALYSIS SUMMARY\n")
        f.write(f"=" * 40 + "\n\n")
        f.write(f"File analyzed: {filepath}\n")
        f.write(f"Benchmark period: {benchmark_start} to {benchmark_end}\n")
        f.write(f"Total metrics: {len(metrics)}\n")
        f.write(f"Successful: {len(successful_metrics)}\n")
        f.write(f"Failed: {len(failed_metrics)}\n")
        f.write(f"Empty: {len(empty_metrics)}\n")
        f.write(f"Plots created: {plot_count}\n\n")
        
        if failed_metrics:
            f.write("FAILED METRICS:\n")
            for metric in failed_metrics:
                f.write(f"  - {metric}\n")
            f.write("\n")
        
        if empty_metrics:
            f.write("EMPTY METRICS:\n")
            for metric in empty_metrics:
                f.write(f"  - {metric}\n")
            f.write("\n")
        
        f.write("SUCCESSFUL METRICS:\n")
        for metric in successful_metrics:
            f.write(f"  - {metric}\n")
    
    print(f"Analysis summary saved: {summary_path}")
    
    return {
        'total': len(metrics),
        'successful': len(successful_metrics),
        'failed': len(failed_metrics),
        'empty': len(empty_metrics),
        'plots_created': plot_count
    }

if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description='Analyze Thanos metrics and create plots')
    parser.add_argument('input_file', help='Path to the Thanos results JSON file')
    parser.add_argument('--output-dir', default='plots', help='Output directory for plots (default: plots)')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.input_file):
        print(f"File not found: {args.input_file}")
        sys.exit(1)
    
    try:
        results = analyze_metrics_file(args.input_file, args.output_dir)
        print(f"\nAnalysis complete! Check the '{args.output_dir}/' directory for plots.")
    except Exception as e:
        print(f"Analysis failed: {e}")
        sys.exit(1) 