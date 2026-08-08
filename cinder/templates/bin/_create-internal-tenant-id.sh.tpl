#!/bin/bash

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

set -ex


USER_PROJECT_ID=$(openstack project create --or-show --enable -f value -c id \
    --domain="${PROJECT_DOMAIN_ID}" \
    "${INTERNAL_PROJECT_NAME}");

# Cinder's internal tenant user is an implementation identity, not an
# interactive/service-login account. Keystone security_compliance password_regex
# nevertheless requires local-user creation to carry a valid string password.
# Supply a high-entropy one-time bootstrap password only on the create attempt.
# With --or-show an existing user is returned without changing its credential.
# The generated value is deliberately neither persisted nor logged, leaving the
# internal identity without an operationally usable shared credential.
set +x
INTERNAL_BOOTSTRAP_PASSWORD="$(cat /proc/sys/kernel/random/uuid)$(cat /proc/sys/kernel/random/uuid)"
USER_ID=$(openstack user create --or-show --enable -f value -c id \
    --domain="${USER_DOMAIN_ID}" \
    --project-domain="${PROJECT_DOMAIN_ID}" \
    --project="${USER_PROJECT_ID}" \
    --password="${INTERNAL_BOOTSTRAP_PASSWORD}" \
    "${INTERNAL_USER_NAME}");
create_exit=$?
unset INTERNAL_BOOTSTRAP_PASSWORD
set -x

if [[ ${create_exit} -ne 0 ]]; then
  echo "Failed to create or resolve Cinder internal user ${INTERNAL_USER_NAME}" >&2
  exit "${create_exit}"
fi

