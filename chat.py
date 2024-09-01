from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
import base64
import requests
import os
import certifi
from flask_cors import CORS

os.environ['REQUESTS_CA_BUNDLE'] = certifi.where()
app = Flask(__name__)
CORS(app)  

API_KEY = 'sk-proj-cbHRYtAtVuSFmar0ZkbVT3BlbkFJR9mMfFdSKIi0PPg0lpTK'

conversation = []


def gpt_interaction(messages):
    try:

        payload = {
            "model": "gpt-4o",
            "messages": messages,
            "max_tokens": 450
        }


        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}"
        }
        response = requests.post("https://api.openai.com/v1/chat/completions", headers=headers, json=payload)

        if response.status_code == 200:
            return response.json()
        else:
            return {"error": f"Failed to generate response from GPT. Status code: {response.status_code}"}

    except Exception as e:
        return {"error": f"Exception occurred: {str(e)}"}

def encode_image(image_path):
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

@app.route('/analyze-image', methods=['POST'])
def analyze_image():
    try:
        global conversation
        conversation = []  
        if 'image' not in request.files:
            return jsonify({"error": "No file part"})

        file = request.files['image']


        if file.filename == '':
            return jsonify({"error": "No selected file"})

        if file:

            filename = secure_filename(file.filename)
            if not os.path.exists(app.config['UPLOAD_FOLDER']):
                os.makedirs(app.config['UPLOAD_FOLDER'])
            image_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
            file.save(image_path)

            base64_image = encode_image(image_path)


            initial_message = [
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Describe this food item. Also try to estimate its precise calorie content range, if you are not able to accurately tell exact caloric value then ask user questions to achieve it. Also ask users at the end if there is anything specific that they want to mention or anything that your response is missing"
                        },
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:image/jpeg;base64,{base64_image}"
                            }
                        }
                    ]
                }
            ]


            gpt_response = gpt_interaction(initial_message)
            if 'choices' in gpt_response and 'message' in gpt_response['choices'][0]:
                conversation.append(initial_message[0])
                conversation.append(gpt_response['choices'][0]['message'])
                return jsonify(gpt_response)
            else:
                return jsonify(gpt_response)


    except Exception as e:
        return jsonify({"error": str(e)})


# Route to handle follow-up messages
@app.route('/chat', methods=['POST'])
def chat():
    try:
        global conversation

        user_message = request.json.get('message')
        conversation.append({"role": "user", "content": user_message})


        gpt_response = gpt_interaction(conversation)
        if 'choices' in gpt_response and 'message' in gpt_response['choices'][0]:
            conversation.append(gpt_response['choices'][0]['message'])
            return jsonify(gpt_response)

        else:
            return jsonify(gpt_response)

    except Exception as e:
        return jsonify({"error": str(e)})

if __name__ == '__main__':
    app.config['UPLOAD_FOLDER'] = './uploads'
    

    app.run(debug=True, host='0.0.0.0', port=5000) 
