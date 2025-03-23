# Use the official AWS Lambda Python base image
FROM public.ecr.aws/lambda/python:3.8

# Set the working directory inside the container
WORKDIR /var/task

# Copy the current directory contents into the container
COPY . .

# Install required Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Set the Lambda function handler
CMD ["lambda_function.lambda_handler"]