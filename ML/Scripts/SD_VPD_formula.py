import pandas as pd
import numpy as np

def saturation_deficit(rh, t):
    up = 0.0621 * t
    p1 = (1 - np.divide(rh, 100))
    p2 = 4.9463 * np.exp(up)
    r = p1 * p2
    return np.round(r, decimals=2)

def vapour_pressure_deficit(rh, t):
    up = np.divide(17.27 * t, 273.3 + t)
    p1 = (1 - np.divide(rh, 100))
    p2 = 0.611 * np.exp(up)
    r = p1 * p2
    return np.round(r, decimals=2)

df = pd.read_csv('weather_1516_mon.csv')
df["sd"] = saturation_deficit(df['rel_hum'],df['mean_temp'])
df["vp"] = vapour_pressure_deficit(df['rel_hum'],df['mean_temp'])
#print(df["sd"])
#print (df['vp'])

df.to_csv('weather_1516_mon.csv')
