import os
import pandas as pd
from sqlalchemy import create_engine

# Password is read from an environment variable — never hardcode credentials.
# Set it before running

password = os.environ.get("PG_PASSWORD")

engine = create_engine(f"postgresql://postgres:{****}@localhost:5432/sales_analysis")

df = pd.read_sql("SELECT * FROM clean_sales LIMIT 5;", engine)
print(df)
