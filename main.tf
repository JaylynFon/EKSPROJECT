# Configure the AWS Provider  
provider "aws" {  
  region = "us-east-1"  
}  
  
# Create a VPC  
resource "aws_vpc" "main" {  
  cidr_block = "10.0.0.0/16"  
  tags = {  
   Name = "eks-vpc"  
  }  
}  

resource "aws_internet_gateway" "main" {  
  vpc_id = aws_vpc.main.id  
  
  tags = {  
   Name = "igw-main"  
  }  
}  
  
# Create public subnets  
resource "aws_subnet" "public" {  
  count = 2  
  
  vpc_id        = aws_vpc.main.id  
  cidr_block      = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)  
  availability_zone = data.aws_availability_zones.available.names[count.index]  
  map_public_ip_on_launch = true  
  
  tags = {  
   Name = "eks-public-subnet-${count.index}"  
  }  
}  
  
# Create private subnets  
resource "aws_subnet" "private" {  
  count = 2  
  
  vpc_id        = aws_vpc.main.id  
  cidr_block      = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 2)  
  availability_zone = data.aws_availability_zones.available.names[count.index]  
  
  tags = {  
   Name = "eks-private-subnet-${count.index}"  
  }  
}  
  
# Get availability zones  
data "aws_availability_zones" "available" {  
  state = "available"  
}  
  
# Create an EKS cluster  
resource "aws_eks_cluster" "main" {  
  name    = "eks-cluster"  
  role_arn = aws_iam_role.eks_cluster.arn  
  
  vpc_config {  
   subnet_ids = aws_subnet.private[*].id  
  }  
  
  depends_on = [  
   aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,  
   aws_iam_role_policy_attachment.eks_cluster_AmazonEKSVPCResourceController,  
  ]  
}  
  
# Create EKS node group  
resource "aws_eks_node_group" "main" {  
  cluster_name   = aws_eks_cluster.main.name  
  node_group_name = "eks-nodes"  
  node_role_arn  = aws_iam_role.eks_node.arn  
  
  subnet_ids = aws_subnet.private[*].id  
  
  instance_types = ["t3.medium"]  
  
  scaling_config {  
   desired_size = 2  
   max_size    = 3  
   min_size    = 1  
  }  
  
  depends_on = [  
   aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,  
   aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,  
   aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy,  
  ]  
}  
  
# Create security group for EKS cluster  
resource "aws_security_group" "eks_cluster" {  
  name      = "eks-cluster-sg"  
  description = "EKS cluster security group"  
  vpc_id    = aws_vpc.main.id  
  
  egress {  
   from_port  = 0  
   to_port    = 0  
   protocol   = "-1"  
   cidr_blocks = ["0.0.0.0/0"]  
  }  
  
  tags = {  
   Name = "eks-cluster-sg"  
  }  
}  
  
# Create security group for EKS nodes  
resource "aws_security_group" "eks_nodes" {  
  name      = "eks-nodes-sg"  
  description = "EKS nodes security group"  
  vpc_id    = aws_vpc.main.id  
  
  egress {  
   from_port  = 0  
   to_port    = 0  
   protocol   = "-1"  
   cidr_blocks = ["0.0.0.0/0"]  
  }  
  
  tags = {  
   Name = "eks-nodes-sg"  
  }  
}  
  
# Create IAM role for EKS cluster  
resource "aws_iam_role" "eks_cluster" {  
  name      = "eks-cluster-role"  
  description = "EKS cluster IAM role"  
  
  assume_role_policy = jsonencode({  
   Version = "2012-10-17"  
   Statement = [  
    {  
      Action = "sts:AssumeRole"  
      Principal = {  
       Service = "eks.amazonaws.com"  
      }  
      Effect = "Allow"  
    },  
   ]  
  })  
}  
  
# Create IAM role for EKS nodes  
resource "aws_iam_role" "eks_node" {  
  name      = "eks-node-role"  
  description = "EKS node IAM role"  
  
  assume_role_policy = jsonencode({  
   Version = "2012-10-17"  
   Statement = [  
    {  
      Action = "sts:AssumeRole"  
      Principal = {  
       Service = "ec2.amazonaws.com"  
      }  
      Effect = "Allow"  
    },  
   ]  
  })  
}  
  
# Attach policies to EKS cluster IAM role  
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {  
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"  
  role     = aws_iam_role.eks_cluster.name  
}  
  
resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSVPCResourceController" {  
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"  
  role     = aws_iam_role.eks_cluster.name  
}  
  
# Attach policies to EKS node IAM role  
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {  
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"  
  role     = aws_iam_role.eks_node.name  
}  
  
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {  
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"  
  role     = aws_iam_role.eks_node.name  
}  
  
resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {  
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"  
  role     = aws_iam_role.eks_node.name  
}  
  
# Create Application Load Balancer  
resource "aws_lb" "main" {  
  name          = "eks-alb"  
  internal        = false  
  load_balancer_type = "application"  
  security_groups   = [aws_security_group.eks_cluster.id]  
  subnets        = aws_subnet.public[*].id  
  
  enable_deletion_protection = false  
}  
  

# Enable versioning for S3 bucket  
resource "aws_s3_bucket_versioning" "myprojectbucket" {  
  bucket = aws_s3_bucket.myprojectbucket.id  
  versioning_configuration {  
   status = "Enabled"  
  }  
}  
  
# Enable server-side encryption for S3 bucket  
resource "aws_s3_bucket_server_side_encryption_configuration" "myprojectbucket" {  
  bucket = aws_s3_bucket.myprojectbucket.id  
  rule {  
   apply_server_side_encryption_by_default {  
    sse_algorithm = "AES256"  
   }  
  }  
}  
  
# Set ACL for S3 bucket  
resource "aws_s3_bucket_acl" "myprojectbucket" {  
  bucket = aws_s3_bucket.myprojectbucket.id  
  acl   = "private"  
}

# Create S3 bucket  
resource "aws_s3_bucket" "myprojectbucket" {  
  bucket = "eks-bucket" 
}  
  