# 1. Generate a private key
openssl genrsa -out developer-abdulah.key 2048

# 2. Create the CSR (CN = username, O = group)
openssl req -new -key developer-abdulah.key \
  -out developer-abdulah.csr \
  -subj "/CN=abdulah/O=devs"


  kubectl config set-credentials abdulah \
  --client-certificate=abdulah.crt \
  --client-key=developer-abdulah.key \
  --embed-certs=true

# 2. Create a context for this user
kubectl config set-context abdulah-context \
  --cluster=kubernetes \
  --user=abdulah

# 3. Switch to the new user
kubectl config use-context abdulah-context