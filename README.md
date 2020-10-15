# Infrastructure
This code of terraform will create AWS VPC infrastructure which includes 
creating a VPC, 3 subnets in 3 different Availability regions, an Internet Gateway to connect to the internet,
 a Route table and a Security Group.

# Installing Terraform

## Prequisite:
    
   Install terraform on your local machine.
   Follow the steps given in the following link:
   https://learn.hashicorp.com/tutorials/terraform/install-cli

## Install AWS CLI and Configure
   Install AWS CLI on your machine.
   Follow the steps given in the following link:
   https://docs.aws.amazon.com/cli/latest/userguide/install-cliv1.html
* Make sure you have the required permission to perform creation of the infrastructure successfully

* If not, attach `AmazonVPCFullAccess` Policy

* Create your AWS profile using:
    ```shell script
    $ aws configure --profile [profile_name]
    ```
    
* Set your AWS profile in your terminal by:

    ```sh
    $ export AWS_PROFILE=[profile_name]
    ```

## Terraform Script Commands

* The terraform init command is used to initialize a working directory containing Terraform configuration files. This is the first command that should be run after writing a new Terraform configuration or cloning an existing one from version control.

    ```sh
    $ terraform init
    ```
* The terraform apply command is used to apply the changes required to reach the desired state of the configuration

    ```sh
    $ terraform apply
    ```

* The terraform destroy command is used to destroy the Terraform-managed infrastructure.

    ```sh
    $ terraform destroy
    ```

## Instructions to Run:

1. Clone the repository

2. run `terraform plan` to plan the terraform configuration

3.  run `terraform apply` to input the resource values via command line. This is the script to create a stack to setup AWS network infrastructure.

3. run `terraform destroy` and input all the required parameters specific to that particular VPC. This is to terminate the entire network stack.

## Files Information

1.  "vpc.tf"     - This file has the entire network infrastructure that will setup all networking resources.
2.  "variables.tf" - All the initialized variables in main.tf must be defined with appropriate type and description in this particular file.