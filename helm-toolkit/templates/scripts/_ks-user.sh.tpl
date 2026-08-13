{{/*
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

{{- define "helm-toolkit.scripts.keystone_user" }}
#!/bin/bash

# Copyright 2017 Pete Birley
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -ex

shopt -s nocasematch

if [[ "${SERVICE_OS_PROJECT_DOMAIN_NAME}" == "Default" ]]
then
  PROJECT_DOMAIN_ID="default"
else
  # Manage project domain
  PROJECT_DOMAIN_ID=$(openstack domain create --or-show --enable -f value -c id \
    --description="Domain for ${SERVICE_OS_PROJECT_DOMAIN_NAME}" \
    "${SERVICE_OS_PROJECT_DOMAIN_NAME}")
fi

if [[ "${SERVICE_OS_USER_DOMAIN_NAME}" == "Default" ]]
then
  USER_DOMAIN_ID="default"
else
  # Manage user domain
  USER_DOMAIN_ID=$(openstack domain create --or-show --enable -f value -c id \
    --description="Domain for ${SERVICE_OS_USER_DOMAIN_NAME}" \
    "${SERVICE_OS_USER_DOMAIN_NAME}")
fi

shopt -u nocasematch

# Manage user project
USER_PROJECT_DESC="Service Project for ${SERVICE_OS_PROJECT_DOMAIN_NAME}"
USER_PROJECT_ID=$(openstack project create --or-show --enable -f value -c id \
    --domain="${PROJECT_DOMAIN_ID}" \
    --description="${USER_PROJECT_DESC}" \
    "${SERVICE_OS_PROJECT_NAME}");

# Manage user. Supplying the candidate password on initial creation is required
# when Keystone [security_compliance] password_regex is enabled: Keystone rejects
# password-less local-user creation before a later password update can run.
# Keep xtrace disabled around password-bearing commands so the service password
# cannot leak into Kubernetes Job logs. With --or-show, an existing user is
# returned without changing its password.
USER_DESC="Service User for ${SERVICE_OS_REGION_NAME}/${SERVICE_OS_USER_DOMAIN_NAME}/${SERVICE_OS_SERVICE_NAME}"
set +x
USER_ID=$(openstack user create --or-show --enable -f value -c id \
    --domain="${USER_DOMAIN_ID}" \
    --project-domain="${PROJECT_DOMAIN_ID}" \
    --project="${USER_PROJECT_ID}" \
    --description="${USER_DESC}" \
    --password="${SERVICE_OS_PASSWORD}" \
    "${SERVICE_OS_USERNAME}");
create_exit=$?
set -x

if [[ ${create_exit} -ne 0 ]]; then
  echo "Failed to create or resolve Keystone user ${SERVICE_OS_USERNAME}" >&2
  exit "${create_exit}"
fi

function ks_assign_user_role () {
  if [[ "$SERVICE_OS_ROLE" == "admin" ]]
  then
    USER_ROLE_ID="$SERVICE_OS_ROLE"
  else
    USER_ROLE_ID=$(openstack role create --or-show -f value -c id "${SERVICE_OS_ROLE}");
  fi

  # Manage user role assignment
  openstack role add \
      --user="${USER_ID}" \
      --user-domain="${USER_DOMAIN_ID}" \
      --project-domain="${PROJECT_DOMAIN_ID}" \
      --project="${USER_PROJECT_ID}" \
      "${USER_ROLE_ID}"
}

# Assign roles before validating the desired service credential. A newly-created
# user cannot issue a project-scoped token until it has at least one assignment.
IFS=','
for SERVICE_OS_ROLE in ${SERVICE_OS_ROLES}; do
  ks_assign_user_role
done

: ${MEMBER_OS_ROLE:="member"}
export USER_ROLE_ID=$(openstack role create --or-show -f value -c id \
    "${MEMBER_OS_ROLE}");
ks_assign_user_role

# Keystone password-history enforcement rejects re-setting the current password.
# Make this job genuinely idempotent: first authenticate with the desired service
# credential. If that works, the password is already current and must not be
# written again. If authentication fails, perform an explicit password rotation
# and verify the rotated credential before declaring the bootstrap successful.
set +x
if OS_USERNAME="${SERVICE_OS_USERNAME}" \
   OS_PASSWORD="${SERVICE_OS_PASSWORD}" \
   OS_PROJECT_NAME="${SERVICE_OS_PROJECT_NAME}" \
   OS_PROJECT_DOMAIN_NAME="${SERVICE_OS_PROJECT_DOMAIN_NAME}" \
   OS_USER_DOMAIN_NAME="${SERVICE_OS_USER_DOMAIN_NAME}" \
   OS_REGION_NAME="${SERVICE_OS_REGION_NAME}" \
   openstack token issue >/dev/null 2>&1; then
  desired_password_valid=true
else
  desired_password_valid=false
fi
set -x

if [[ "${desired_password_valid}" == "true" ]]; then
  echo "Keystone service credential already matches desired state; password update skipped"
else
  set +x
  echo "Desired Keystone service credential does not authenticate; rotating password for ${SERVICE_OS_USERNAME}"
  if openstack user set --password="${SERVICE_OS_PASSWORD}" "${USER_ID}"; then
    password_update_exit=0
  else
    password_update_exit=$?
  fi
  set -x

  if [[ ${password_update_exit} -ne 0 ]]; then
    echo "Failed to rotate Keystone password for ${SERVICE_OS_USERNAME}" >&2
    exit "${password_update_exit}"
  fi

  set +x
  if OS_USERNAME="${SERVICE_OS_USERNAME}" \
     OS_PASSWORD="${SERVICE_OS_PASSWORD}" \
     OS_PROJECT_NAME="${SERVICE_OS_PROJECT_NAME}" \
     OS_PROJECT_DOMAIN_NAME="${SERVICE_OS_PROJECT_DOMAIN_NAME}" \
     OS_USER_DOMAIN_NAME="${SERVICE_OS_USER_DOMAIN_NAME}" \
     OS_REGION_NAME="${SERVICE_OS_REGION_NAME}" \
     openstack token issue >/dev/null 2>&1; then
    credential_verify_exit=0
  else
    credential_verify_exit=$?
  fi
  set -x

  if [[ ${credential_verify_exit} -ne 0 ]]; then
    echo "Keystone service credential verification failed after password rotation for ${SERVICE_OS_USERNAME}" >&2
    exit "${credential_verify_exit}"
  fi
fi
{{- end }}
