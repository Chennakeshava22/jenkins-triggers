pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = "us-east-1"
    }

    parameters {
        booleanParam(name: 'PLAN_TERRAFORM', defaultValue: true, description: 'Run terraform plan')
        booleanParam(name: 'APPLY_TERRAFORM', defaultValue: false, description: 'Run terraform apply')
        booleanParam(name: 'DESTROY_TERRAFORM', defaultValue: false, description: 'Run terraform destroy')
    }

    stages {

        stage('Clone Repository') {
            steps {
                deleteDir() // Clean workspace
                git branch: 'main',
                    url: 'https://github.com/Chennakeshava22/terraform-devops-project.git'
                sh "ls -lart" // List files to confirm structure
            }
        }

        stage('Terraform Init') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-crendentails-rwagh']]) {
                    sh 'echo "================= Terraform Init =================="'
                    sh 'terraform init'
                }
            }
        }

        stage('Terraform Plan') {
            when {
                expression { params.PLAN_TERRAFORM }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-crendentails-rwagh']]) {
                    sh 'echo "================= Terraform Plan =================="'
                    sh 'terraform plan'
                }
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.APPLY_TERRAFORM }
            }
            steps {
                input message: 'Approve deployment?'
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-crendentails-rwagh']]) {
                    sh 'echo "================= Terraform Apply =================="'
                    sh 'terraform apply -auto-approve'
                }
            }
        }

        stage('Terraform Destroy') {
            when {
                expression { params.DESTROY_TERRAFORM }
            }
            steps {
                input message: 'Are you sure you want to destroy the infrastructure?'
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-crendentails-rwagh']]) {
                    sh 'echo "================= Terraform Destroy =================="'
                    sh 'terraform destroy -auto-approve'
                }
            }
        }

    }
}

