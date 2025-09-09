#!/usr/bin/env python3
import json
import matplotlib
matplotlib.use('Agg')  # Use non-interactive backend
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from datetime import datetime
import os
import sys
import glob

def parse_timestamp(ts_str):
    """Parse ISO timestamp string to datetime object"""
    try:
        return datetime.fromisoformat(ts_str.replace('Z', '+00:00'))
    except:
        return datetime.now()

def plot_metric(metric_name, metric_data, output_dir, benchmark_start, benchmark_end):
    """Plot a single metric and save as PNG"""
    try:
        if 'data' not in metric_data or 'result' not in metric_data['data']:
            print(f"No data found for metric: {metric_name}")
            return
        
        results = metric_data['data']['result']
        if not results:
            print(f"Empty results for metric: {metric_name}")
            return
        
        plt.figure(figsize=(12, 6))
        
        for i, result in enumerate(results):
            if 'values' not in result:
                continue
                
            timestamps = []
            values = []
            
            for value_pair in result['values']:
                # value_pair is [timestamp, value]
                ts = datetime.fromtimestamp(float(value_pair[0]))
                val = float(value_pair[1]) if value_pair[1] != 'NaN' else 0
                timestamps.append(ts)
                values.append(val)
            
            if not timestamps:
                continue
                
            # Create label from metric labels
            label = metric_name
            if 'metric' in result and result['metric']:
                labels = []
                for key, value in result['metric'].items():
                    if key not in ['__name__']:
                        labels.append(f"{key}={value}")
                if labels:
                    label = f"{metric_name} ({', '.join(labels[:2])})"  # Limit to 2 labels
            
            plt.plot(timestamps, values, label=label, marker='o', markersize=2, linewidth=1)
        
        plt.title(f'{metric_name}\nBenchmark Period: {benchmark_start} to {benchmark_end}')
        plt.xlabel('Time')
        plt.ylabel('Value')
        plt.grid(True, alpha=0.3)
        plt.xticks(rotation=45)
        
        # Format x-axis
        plt.gca().xaxis.set_major_formatter(mdates.DateFormatter('%H:%M:%S'))
        plt.gca().xaxis.set_major_locator(mdates.SecondLocator(interval=30))
        
        # Add legend if multiple series
        if len(results) > 1:
            plt.legend(bbox_to_anchor=(1.05, 1), loc='upper left')
        
        plt.tight_layout()
        
        # Save plot
        safe_name = metric_name.replace(':', '_').replace('/', '_')
        output_file = os.path.join(output_dir, f'{safe_name}.png')
        plt.savefig(output_file, dpi=150, bbox_inches='tight')
        plt.close()
        
        print(f"Generated plot: {output_file}")
        
    except Exception as e:
        print(f"Error plotting {metric_name}: {str(e)}")

def main():
    if len(sys.argv) != 2:
        print("Usage: python plot_metrics.py <output_directory>")
        sys.exit(1)
    
    output_dir = sys.argv[1]
    
    # Find the most recent Thanos results file
    pattern = os.path.join(output_dir, "results-thanos-*.json")
    files = glob.glob(pattern)
    
    if not files:
        print(f"No Thanos results files found in {output_dir}")
        sys.exit(1)
    
    # Use the most recent file
    latest_file = max(files, key=os.path.getctime)
    print(f"Processing metrics from: {latest_file}")
    
    try:
        with open(latest_file, 'r') as f:
            data = json.load(f)
        
        benchmark_start = data.get('benchmark_start', 'Unknown')
        benchmark_end = data.get('benchmark_end', 'Unknown')
        metrics = data.get('metrics', {})
        
        print(f"Found {len(metrics)} metrics to plot")
        print(f"Benchmark period: {benchmark_start} to {benchmark_end}")
        
        # Create plots for each metric
        for metric_name, metric_data in metrics.items():
            plot_metric(metric_name, metric_data, output_dir, benchmark_start, benchmark_end)
        
        print(f"All plots saved to: {output_dir}")
        
    except Exception as e:
        print(f"Error processing file {latest_file}: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main() 