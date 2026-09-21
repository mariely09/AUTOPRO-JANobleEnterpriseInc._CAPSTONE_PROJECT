"""
Test script for AI streaming endpoint

Usage:
    python test_streaming.py

This script tests the /admin/chat/stream endpoint to verify:
1. Streaming functionality works
2. Chunks arrive in real-time
3. Session management persists
4. Stop generation works (Ctrl+C)
"""

import requests
import json
import time
import sys

# Backend URL
BASE_URL = "https://caltex-autopro-capstone-project.onrender.com"
# BASE_URL = "http://localhost:8000"  # Uncomment for local testing

def test_streaming_endpoint(message: str, session_id: str = None):
    """Test the streaming chat endpoint"""
    
    url = f"{BASE_URL}/admin/chat/stream"
    payload = {
        "message": message,
        "session_id": session_id
    }
    
    print(f"\n{'='*80}")
    print(f"Testing: {message}")
    print(f"Session: {session_id or 'NEW'}")
    print(f"{'='*80}\n")
    
    start_time = time.time()
    first_token_time = None
    chunk_count = 0
    accumulated_text = ""
    final_session_id = None
    
    try:
        with requests.post(url, json=payload, stream=True, timeout=60) as response:
            if response.status_code != 200:
                print(f"❌ Error: HTTP {response.status_code}")
                print(response.text)
                return None
            
            print("✓ Connection established")
            print("✓ Streaming started...\n")
            print("-" * 80)
            
            for line in response.iter_lines():
                if not line:
                    continue
                
                line_str = line.decode('utf-8')
                
                # Parse SSE format: data: {...}
                if line_str.startswith('data: '):
                    json_str = line_str[6:]  # Remove "data: " prefix
                    
                    try:
                        data = json.loads(json_str)
                        
                        # Handle error
                        if 'error' in data:
                            print(f"\n❌ Error: {data['error']}")
                            break
                        
                        # Handle chunk
                        if 'chunk' in data:
                            chunk = data['chunk']
                            accumulated_text += chunk
                            chunk_count += 1
                            
                            # Record time to first token
                            if first_token_time is None:
                                first_token_time = time.time()
                                ttft = first_token_time - start_time
                                print(f"⚡ FIRST TOKEN: {ttft:.3f}s\n")
                            
                            # Print chunk in real-time
                            print(chunk, end='', flush=True)
                        
                        # Handle completion
                        if data.get('done'):
                            final_session_id = data.get('session_id')
                            break
                    
                    except json.JSONDecodeError:
                        continue
            
            print("\n" + "-" * 80)
            
            # Summary
            total_time = time.time() - start_time
            ttft = first_token_time - start_time if first_token_time else total_time
            
            print(f"\n📊 Performance Metrics:")
            print(f"   Time to First Token: {ttft:.3f}s")
            print(f"   Total Time: {total_time:.3f}s")
            print(f"   Chunks Received: {chunk_count}")
            print(f"   Total Characters: {len(accumulated_text)}")
            print(f"   Session ID: {final_session_id}")
            
            if ttft < 2.0:
                print(f"   ✅ TTFT Target Met (<2s)")
            else:
                print(f"   ⚠️  TTFT Above Target (>{ttft:.1f}s)")
            
            return final_session_id
    
    except KeyboardInterrupt:
        print("\n\n⏹️  Streaming stopped by user (Ctrl+C)")
        return None
    except requests.exceptions.Timeout:
        print("\n❌ Request timed out")
        return None
    except Exception as e:
        print(f"\n❌ Error: {e}")
        return None


def run_tests():
    """Run a series of tests"""
    
    print("=" * 80)
    print("AI STREAMING ENDPOINT TEST SUITE")
    print("=" * 80)
    
    # Test 1: Simple greeting (should be instant via simple_conversation)
    print("\n\n🧪 TEST 1: Simple Greeting (Fast-Path)")
    session_id = test_streaming_endpoint("Hello")
    time.sleep(1)
    
    # Test 2: Arithmetic (should be instant via fast-path)
    print("\n\n🧪 TEST 2: Arithmetic (Fast-Path)")
    test_streaming_endpoint("What is 250 minus 75?", session_id)
    time.sleep(1)
    
    # Test 3: General AI question (should stream)
    print("\n\n🧪 TEST 3: General AI Question (Streaming)")
    test_streaming_endpoint("What is preventive maintenance?", session_id)
    time.sleep(1)
    
    # Test 4: Database query (fast-path with instant data)
    print("\n\n🧪 TEST 4: Database Query (Fast-Path)")
    test_streaming_endpoint("Show me low stock items", session_id)
    time.sleep(1)
    
    # Test 5: Out of scope (should be instant blocked)
    print("\n\n🧪 TEST 5: Out of Scope (Fast-Path Block)")
    test_streaming_endpoint("What's the weather today?", session_id)
    
    print("\n\n" + "=" * 80)
    print("✅ ALL TESTS COMPLETED")
    print("=" * 80)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        # Single test with custom message
        message = " ".join(sys.argv[1:])
        test_streaming_endpoint(message)
    else:
        # Run full test suite
        try:
            run_tests()
        except KeyboardInterrupt:
            print("\n\n⏹️  Tests interrupted by user")
