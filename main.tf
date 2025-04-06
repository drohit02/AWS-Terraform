module "AWS-VPC" {
  source = "./AWS-VPC"
}

// Resource : Private subnet --> if require more subnets,uncommenetd this section
/*
module "AWS-Private-Subent" {
  source = "./AWS-Private-Subnet"
}
*/

//Resource : Aurora Postrgres Database : If required uncommented this
/*
module "AWS-RDS" {
  source = "./AWS-RDS"
}
*/

//Resource : AWS Lambda with DB Configuration : sample code AWS Lambda access RDS in private subnets
/*
module "AWS-Lambda-with-DB-Configure" {
  source = "./AWS-Lambda/Lambda-RDS"
  
}
*/

//Resource : AWS Lambda with Aurora DB Connectivity : Full-Flege Code with Application code
/*
module "AWS-Lamnda-with-AuroraDB" {
  source = "./AWS-Lambda/Lambda-AuroraDB"
  
}
*/
