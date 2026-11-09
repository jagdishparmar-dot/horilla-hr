# Clone and setup (defaults to the stable 2.0 branch)
git clone https://github.com/horilla/horilla-hr.git
cd horilla-hr

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Upgrade pip FIRST. A venv inherits the system pip, and an older one does not
# recognise current manylinux wheel tags -- it then tries to compile packages
# like cryptography and PyMuPDF from source, which needs a C toolchain most
# machines do not have. The Docker build already does this; do the same here.
python -m pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt

# Setup environment
cp .env.dist .env
# Edit .env with your configuration

# Initialize database
python manage.py migrate
python manage.py compilemessages
python manage.py collectstatic

# Run development server
python manage.py runserver

# In a second terminal: run the background scheduler
python manage.py run_scheduler