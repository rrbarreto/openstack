#! /bin/sh

#
# Simple script to create a new project on OpenStack.
#
# This script is responsible for create:
# - Project (Tenant)   
# - User
# - Quota
# - Base network
#

#
# [PROJECT]
#
PROJECT_NAME=""
PROJECT_DESCRIPTION=""

#
# [USER]
#
USER_NAME=""
USER_EMAIL=""
USER_PASS=""

#
# [QUOTA]
#
# Amount of cores vCPU 
# CPU="4"
CPU="8"

# Amount of memory in MB.
# Eg 8G: ( 8 * 1024) = 8192 MB
# RAM="8192"
RAM="8192"

# Amount of floating IP
# FLOATING_IP="1"
FLOATING_IP="4"

# Total Size of Volumes and Snapshots in GB
# DISK_SIZE="50"
DISK_SIZE="250"

#
# [NETWORK]
#
ROUTER_NAME="roteador" 
NET_NAME="privada"
SUB_NAME="sub_privada" 
SUB_CIDR="192.168.0.0/24"
SUB_GW="192.168.0.1"   
DNS=("8.8.8.8" "8.8.4.4")
EXT_NET="publica"

#
# [DAEMONS]
#
KEYSTONE_BIN="/usr/bin/keystone"
NOVA_BIN="/usr/bin/nova"
CINDER_BIN="/usr/bin/cinder"
NEUTRON_BIN="/usr/bin/neutron"
AWK_BIN="/usr/bin/awk" 
WC_BIN="/usr/bin/wc"   

#
# Fix-me 
#
OS_AUTH_URL="http://public-keystone-endpoint:5000/v2.0/"

#
# NO CHANGE FROM HERE UNLESS
# YOU KNOW WHAT YOU ARE DOING =D
#

main(){
        source /root/keystonerc_admin
        tenant_create  
        user_create
        network_create 
}
# Function to verify if the project exist before create it
tenant_create() {
        if [ `${KEYSTONE_BIN} tenant-list | ${AWK_BIN} '/ '${PROJECT_NAME}' / {print $2}' | ${WC_BIN} -l` -eq 0 ] ; then
                ${KEYSTONE_BIN} tenant-create --name ${PROJECT_NAME} --description "${PROJECT_DESCRIPTION}"
                PROJECT_ID=`${KEYSTONE_BIN} tenant-list | ${AWK_BIN} '/ '${PROJECT_NAME}' / {print $2}'`
                echo "==> Project was created. Project ID is ::: ${PROJECT_ID} :::"
                quota_update
        else
                PROJECT_ID=`${KEYSTONE_BIN} tenant-list | ${AWK_BIN} '/ '${PROJECT_NAME}' / {print $2}'`
                echo "==> Tenant ${PROJECT_NAME} already exist, your ID is ::: ${PROJECT_ID} :::"
                echo "==> Quota was NOT updated"
        fi
}

# Function to verify if the user exist before create it
user_create(){
        if [ `${KEYSTONE_BIN} user-list | ${AWK_BIN} '/ '${USER_NAME}' / {print $2}' | ${WC_BIN} -l` -eq 0 ]; then
                ${KEYSTONE_BIN} user-create --name ${USER_NAME} --tenant ${PROJECT_NAME} --pass "${USER_PASS}" --email ${USER_EMAIL}
                echo "==> Adding user admin to the Project Members"
                ${KEYSTONE_BIN} user-role-add --user=admin --role=_member_ --tenant=${PROJECT_NAME}
        else
                echo "==> User ${USER_NAME} already exist"
        fi
}

# Function to quota update when the project is created
quota_update(){
        ${NOVA_BIN} quota-update --cores ${CPU} --ram ${RAM} ${PROJECT_ID}
        ${NEUTRON_BIN} quota-update --floatingip ${FLOATING_IP} --tenant-id ${PROJECT_ID}
        ${CINDER_BIN} quota-update --gigabytes ${DISK_SIZE} ${PROJECT_ID}
        echo "==> Quotas to Nova, Neutron and Cinder were updated"
}
# Function to verify if network components exist before create it
network_create() {
        # Now we are going to create the base network environment to prior tenant created
        # for this we need export the env variables to keystone user auth.
        #
        # [KEYSTONE_USER_AUTH]
        #
        OS_USERNAME=${USER_NAME}
        OS_TENANT_NAME=${PROJECT_NAME}
        OS_PASSWORD=${USER_PASS}
        OS_AUTH_URL=${OS_AUTH_URL}

        export OS_USERNAME OS_TENANT_NAME OS_PASSWORD OS_AUTH_URL

        # Verify if user env variables
        if [ `env |grep OS_TENANT_NAME |awk -F"=" '{print $2}'` == ${PROJECT_NAME} ] && [ `env |grep OS_USERNAME |awk -F"=" '{print $2}'` == ${USER_NAME} ]; then

                # Verify if exist more than one router with same name
                if [ `${NEUTRON_BIN} router-list | ${AWK_BIN} '/ '${ROUTER_NAME}' / {print $2}' | ${WC_BIN} -l` -ne 0 ]; then
                        echo "==> One or more router with name ${ROUTER_NAME} already exist on tenant ${PROJECT_NAME}"
                fi

                # Verify if exist more than one network with same name
                if [ `${NEUTRON_BIN} net-list | ${AWK_BIN} '/ '${NET_NAME}' / {print $2}' | ${WC_BIN} -l` -ne 0 ]; then
                        echo "==> One or more network with name ${NET_NAME} already exist on tenant ${PROJECT_NAME}"
                fi

                # Verify if exist more than one subnet with same CIDR
                if [ `${NEUTRON_BIN} subnet-list | ${AWK_BIN} '$0~v {print $2}' v=${SUB_CIDR} | ${WC_BIN} -l` -ne 0 ]; then
                        echo "==> One or more subnet with same CIDR ${SUB_CIDR} already exist on tenant ${PROJECT_NAME}"
                fi

                # Create router, network and subnet if don't exist
                if [ `${NEUTRON_BIN} router-list | ${AWK_BIN} '/ '${ROUTER_NAME}' / {print $2}' | ${WC_BIN} -l` -eq 0 ] &&
                   [ `${NEUTRON_BIN} net-list | ${AWK_BIN} '/ '${NET_NAME}' / {print $2}' | ${WC_BIN} -l` -eq 0 ] &&
                   [ `${NEUTRON_BIN} subnet-list | ${AWK_BIN} '$0~v {print $2}' v=${SUB_CIDR} | ${WC_BIN} -l` -eq 0 ]; then

                        ${NEUTRON_BIN} router-create ${ROUTER_NAME}
                        ${NEUTRON_BIN} net-create ${NET_NAME}
                        ${NEUTRON_BIN} subnet-create ${NET_NAME} --name ${SUB_NAME} --gateway ${SUB_GW} ${SUB_CIDR} --enable-dhcp --dns-nameservers ${DNS[@]}
                        ${NEUTRON_BIN} router-interface-add ${ROUTER_NAME} ${SUB_NAME}
                        ${NEUTRON_BIN} router-gateway-set ${ROUTER_NAME} ${EXT_NET}
                        echo "==> Base network was created"
                fi
        else
                echo "==> Base network was NOT created"
        fi
}

# Run main function
main


