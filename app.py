# app.py (Flask Backend)
import os
import cv2
import uuid
import base64
from flask import Flask, request, jsonify,send_from_directory
from flask_cors import CORS
from ultralytics import YOLO
import tempfile
import numpy as np


app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Load your trained YOLO model
model = YOLO("/Users/kirankishore/Downloads/FINAL_WILDLIFE/runs/detect/train/weights/best.pt")  # Update path as needed

# Define your class labels
class_labels = ['Animal', 'Binocular', 'Fire', 'Helicopter', 'Poacher', 'Ranger', 'Vehicle', 'Weapon']

@app.route('/')
def index():
    return send_from_directory('static', 'index.html')

# Route for processing uploaded videos
@app.route('/process_video', methods=['POST'])
def process_video():
    if 'video' not in request.files:
        return jsonify({'error': 'No video file provided'}), 400
    
    video_file = request.files['video']
    
    # Create a temporary file to save the uploaded video
    temp_input = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
    video_file.save(temp_input.name)
    temp_input.close()
    # Create a temporary file for the output video
    temp_output = tempfile.NamedTemporaryFile(delete=False, suffix='.mp4')
    temp_output.close()
    
    # Process the video
    try:
        cap = cv2.VideoCapture(temp_input.name)
        
        # Get video properties
        frame_width = int(cap.get(3))
        frame_height = int(cap.get(4))
        fps = int(cap.get(cv2.CAP_PROP_FPS))
        
        # Define output video file
        out = cv2.VideoWriter(temp_output.name, cv2.VideoWriter_fourcc(*'mp4v'), fps, (frame_width, frame_height))
        
        # Statistics dictionary to return
        stats = {label: 0 for label in class_labels}
        frame_count = 0
        
        # Process video frame by frame
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break  # Stop when video ends
            
            frame_count += 1
            
            # Run YOLOv8 object detection on the frame
            results = model(frame)
            
            # Draw bounding boxes with correct class labels
            for result in results:
                for box in result.boxes:
                    x1, y1, x2, y2 = map(int, box.xyxy[0])  # Bounding box coordinates
                    conf = box.conf[0].item()  # Confidence score
                    cls = int(box.cls[0].item())  # Class index
                    
                    # Ensure the detected class index is within range
                    label = class_labels[cls] if 0 <= cls < len(class_labels) else "Unknown"
                    stats[label] = stats.get(label, 0) + 1
                    
                    # Assign color dynamically
                    if label.lower() in ["hunter", "human", "poacher", "ranger"]:
                        color = (0, 255, 0)  # Green for humans
                    elif label.lower() in ["bike", "car", "jeep", "truck", "van", "helicopter", "vehicle"]:
                        color = (0, 0, 255)  # Red for vehicles
                    else:
                        color = (255, 0, 0)  # Blue for animals
                    
                    # Draw bounding box and label
                    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
                    cv2.putText(frame, f"{label} {conf:.2f}", (x1, y1 - 10),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
            
            # Save processed frame to output video
            out.write(frame)
        
        # Release resources
        cap.release()
        out.release()
        
        # Prepare results to send back
        with open(temp_output.name, 'rb') as f:
            video_data = f.read()
        
        # Convert to base64 for sending to client
        video_base64 = base64.b64encode(video_data).decode('utf-8')
        
        # Clean up temporary files
        os.unlink(temp_input.name)
        os.unlink(temp_output.name)
        
        return jsonify({
            'message': 'Video processed successfully',
            'processed_video': video_base64,
            'statistics': stats,
            'frames_processed': frame_count
        })
    
    except Exception as e:
        # Clean up temporary files in case of error
        if os.path.exists(temp_input.name):
            os.unlink(temp_input.name)
        if os.path.exists(temp_output.name):
            os.unlink(temp_output.name)
        return jsonify({'error': str(e)}), 500

# Route to handle streaming for real-time detection (if needed)
@app.route('/process_frame', methods=['POST'])
def process_frame():
    try:
        # Get the frame from the request
        data = request.json
        if 'frame' not in data:
            return jsonify({'error': 'No frame data provided'}), 400
        
        # Decode base64 image
        encoded_frame = data['frame']
        decoded_frame = base64.b64decode(encoded_frame)
        np_arr = np.frombuffer(decoded_frame, np.uint8)
        frame = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        
        # Run detection
        results = model(frame)
        
        detections = []
        
        # Process results
        for result in results:
            for box in result.boxes:
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                conf = float(box.conf[0].item())
                cls = int(box.cls[0].item())
                
                label = class_labels[cls] if 0 <= cls < len(class_labels) else "Unknown"
                
                detections.append({
                    'label': label,
                    'confidence': conf,
                    'bbox': [x1, y1, x2, y2]
                })
        
        return jsonify({
            'detections': detections
        })
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=True)
