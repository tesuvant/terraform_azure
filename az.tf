
variable "subscription_id" { type = string }
variable "client_id"       { type = string }
variable "client_secret"   { type = string }
variable "tenant_id"       { type = string }
variable "pw"              { type = string }
variable "nsg_hosts_allow" { type = list(string) }

provider "dns" {
  update {
    server = "8.8.8.8"
  }
}

output "inconsult_addrs" {
#  value = "${join(",", data.dns_a_record_set.allow_hosts.addrs)}"
  value = flatten(data.dns_a_record_set.allow_hosts.*.addrs)
  #value = tolist(data.dns_a_record_set.allow_hosts[*])     # returns: addrs, host, id
  #value = "${join(",", data.dns_a_record_set.allow_hosts.*.addrs)}"
}
#   "outputs": {
#     "inconsult_addrs": {
#       "value": [
#         [
#           "35.214.195.220"
#         ],
#         [
#           "35.214.195.220"
#         ]
#       ],
#       "type": [
#         "tuple",
#         [
#           [
#             "list",
#             "string"
#           ],
#           [
#             "list",
#             "string"
#           ]
#         ]
#       ]
#     },
#     "public_ip_address": {
#       "value": "104.46.51.54",
#       "type": "string"
#     }
#   },

 data "dns_a_record_set" "allow_hosts" {
   count = length(var.nsg_hosts_allow)
   host  = var.nsg_hosts_allow[count.index]
 }

# Configure the Azure Provider
provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  version = "=1.42.0"
  
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret
  tenant_id       = var.tenant_id
}


# Create Network Security Group and rule
resource "azurerm_network_security_group" "myterraformnsg" {
    name                = "myNetworkSecurityGroup"
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.myterraformgroup.name
    
    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        #source_address_prefixes    = tolist(data.dns_a_record_set.allow_hosts[*].addrs)
        #source_address_prefixes    = data.dns_a_record_set.allow_hosts[*].addrs
        source_address_prefixes    = flatten(data.dns_a_record_set.allow_hosts.*.addrs)
        #source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
    
    tags = {
        environment = "Terraform Demo"
    }
}

# Create a resource group if it doesn’t exist
resource "azurerm_resource_group" "myterraformgroup" {
    name     = "resource_group_test"
    location = "westeurope"

    tags = {
        environment = "Terraform Demo"
    }
}

# Create virtual network
resource "azurerm_virtual_network" "myterraformnetwork" {
    name                = "myVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "westeurope"
    resource_group_name = azurerm_resource_group.myterraformgroup.name

    tags = {
        environment = "Terraform Demo"
    }
}

# Create subnet
resource "azurerm_subnet" "myterraformsubnet" {
    name                 = "mySubnet"
    resource_group_name  = azurerm_resource_group.myterraformgroup.name
    virtual_network_name = azurerm_virtual_network.myterraformnetwork.name
    address_prefix       = "10.0.1.0/24"
}

# Create public IPs
resource "azurerm_public_ip" "myterraformpublicip" {
    name                         = "myPublicIP"
    location                     = "westeurope"
    resource_group_name          = azurerm_resource_group.myterraformgroup.name
    allocation_method            = "Static"
#    domain_name_label            = "tfiscool"
    tags = {
        environment = "Terraform Demo"
    }
}



# Create network interface
resource "azurerm_network_interface" "myterraformnic" {
    name                      = "myNIC"
    location                  = "westeurope"
    resource_group_name       = azurerm_resource_group.myterraformgroup.name
    network_security_group_id = azurerm_network_security_group.myterraformnsg.id

    ip_configuration {
        name                          = "myNicConfiguration"
        subnet_id                     = azurerm_subnet.myterraformsubnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.myterraformpublicip.id
    }

    tags = {
        environment = "Terraform Demo"
    }
}

# Generate random text for a unique storage account name
resource "random_id" "randomId" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.myterraformgroup.name
    }
    
    byte_length = 8
}

# Create storage account for boot diagnostics
resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "diag${random_id.randomId.hex}"
    resource_group_name         = azurerm_resource_group.myterraformgroup.name
    location                    = "westeurope"
    account_tier                = "Standard"
    account_replication_type    = "LRS"

    tags = {
        environment = "Terraform Demo"
    }
}

# Create virtual machine
resource "azurerm_virtual_machine" "myterraformvm" {
    name                  = "myVM"
    location              = "westeurope"
    resource_group_name   = azurerm_resource_group.myterraformgroup.name
    network_interface_ids = [azurerm_network_interface.myterraformnic.id]
    vm_size               = "Standard_B2S"

    storage_os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        create_option     = "FromImage"
        managed_disk_type = "Premium_LRS"
    }

    storage_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    os_profile {
        computer_name  = "myvm"
        admin_username = "azureuser"
        admin_password = var.pw
    }

    os_profile_linux_config {
        disable_password_authentication = false
        ssh_keys {
            path     = "/home/azureuser/.ssh/authorized_keys"
            key_data = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCircnyEJmCVs/JcYo43kvQGwULLzW4k5KtL3hYAzCL7N26mZXQVQ3EKBJgbX6hRT17aqXMz41mrZgpwpXJQlfQ4XL+BxRP6nSe8K+diy468x3yrQvSsYK9FDMfM6tTcbOzbkrPmTJlI6XaNpi5IZIAEPwQS5BXW/oQKt83BsMzphwW+Ysjbyd5TToQ8TqciqIsSLv6kBC8nGX70JLnSbX0HLmvXP7cTpqRDWz/QokJMUy3wzloAKefH0c6FKEQgvfDjfWJwecP10uvViUSsk2vyhRz+uq1DK9t8ve5Yh5hSEvGDgG9mChLMInkH2TlGBYKUwR//bWHn6ArxQB0XEN/ tsuvanto@sauna"
        }
    }

    boot_diagnostics {
        enabled = "true"
        storage_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
    }

    tags = {
        environment = "Terraform Demo"
    }
}

data "azurerm_public_ip" "pip" {
  name                = azurerm_public_ip.myterraformpublicip.name
  resource_group_name = azurerm_virtual_machine.myterraformvm.resource_group_name
}

output "public_ip_address" {
  value = data.azurerm_public_ip.pip.ip_address
}

# locals {
#   prefix = "sudo /bin/bash -l -c 'echo \""
#   postfix = "\" >> /etc/bash.bashrc'"
#   proxyvars = <<EOF
# export HTTP_PROXY=http://myproxy.foo.bar:3128
# export HTTPS_PROXY=http://myproxy.foo.bar:3128
# export NO_PROXY=.domain.com,.domain.org
# export http_proxy=http://myproxy.foo.bar:3128
# export https_proxy=http://myproxy.foo.bar:3128
# export no_proxy=.domain.com,.domain.org
# EOF
#   proxycmd = "${local.prefix}${local.proxyvars}${local.postfix}"
# }

resource "null_resource" "proxy_env" {
  # trigger this resouce upon 'primary_node' instance finishing
  triggers = {
    cluster_instance_ids = "${azurerm_public_ip.myterraformpublicip.ip_address}"
  }

  connection {
        host        = "${azurerm_public_ip.myterraformpublicip.ip_address}"
        type        = "ssh"
        password    = var.pw
        user        = "azureuser"
        timeout     = "10m"
  }

#   provisioner "remote-exec" {
#       inline = [
#         "set -x",
#         local.proxycmd
#       ]
#   }
}

#resource "azurerm_virtual_machine_extension" "foobar" {
#  name                 = "foobar"
#  virtual_machine_id   = azurerm_virtual_machine.myterraformvm.id
#  publisher            = "Microsoft.Azure.Extensions"
#  type                 = "CustomScript"
#  type_handler_version = "2.0"
#
#  settings = <<EOF
#    {
#        "fileUris": ["https://raw.githubusercontent.com/tesuvant/terraform_azure/master/helloworld.sh"],
#        "commandToExecute": "./helloworld.sh"
#    }
#    EOF
#}

variable "proxyscript" {
  default = <<-SCRIPT
#!/bin/bash
cat << EOF >> /etc/bash.bashrc
### TF MANAGED BLOCK
export HTTP_PROXY=http://foo.bar:8443
export HTTPS_PROXY=http://foo.bar:8443
export NO_PROXY=localhost,127.0.0.1
export http_proxy=http://foo.bar:8443
export https_proxy=http://foo.bar:8443
export no_proxy=localhost,127.0.0.1
### TF MANAGED BLOCK
EOF
SCRIPT
}

resource "azurerm_virtual_machine_extension" "proxy" {
  name                 = "proxy"
  virtual_machine_id   = azurerm_virtual_machine.myterraformvm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.0"

  settings = <<SETTINGS
    {
     "script": "${base64encode(var.proxyscript)}"
    }
SETTINGS
}
