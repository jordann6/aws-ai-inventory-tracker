from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import APIGateway
from diagrams.aws.compute import Lambda
from diagrams.aws.database import Dynamodb
from diagrams.aws.ml import Sagemaker
from diagrams.aws.security import IAM

graph_attrs = {
    "fontsize": "13",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "ortho",
}

node_attrs = {
    "fontsize": "11",
}

with Diagram(
    "AWS AI Inventory Tracker",
    filename="docs/architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attrs,
    node_attr=node_attrs,
):
    apigw = APIGateway("API Gateway v2\nGET/POST /items\nGET/DELETE /items/{id}\nPOST /items/{id}/analyze")

    with Cluster("AWS · us-east-1"):
        fn = Lambda("Lambda\ninventory-api")
        role = IAM("IAM Execution Role\nDynamoDB CRUD + Bedrock InvokeModel")

        with Cluster("DynamoDB · inventory-dev"):
            db = Dynamodb("Inventory Table\nPAY_PER_REQUEST · PITR Enabled")

        bedrock = Sagemaker("Amazon Bedrock\nClaude 3.5 Haiku")

    apigw >> Edge(label="HTTP proxy") >> fn
    fn >> Edge(label="assumes") >> role
    role >> Edge(label="GetItem / PutItem\nDeleteItem / Scan") >> db
    role >> Edge(label="InvokeModel\n(POST /analyze)") >> bedrock
