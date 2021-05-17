import pandas as pd

#Reading the text file "tickbite.txt" and giving the column names.
tick = pd.read_csv("tickbite.txt",sep=" ",header=None,names=['ID','MONTH','AGE','ACTIVITY','LANDUSE','BITE_STATUS'])

#Considering only the data where tick bite status is true.
tick = tick[tick.BITE_STATUS != False]

#Removing the first column of null values.
tick = tick.drop(tick.columns[0], axis=1)

#Removing the last row of null values.
tick = tick.iloc[:-1]

#Removing empty rows
tick.dropna(how="all", inplace=True)

#Converting it to csv file and saving it as 'tickbite_final.csv'.
tick.to_csv('tickbite_final.csv',index=False)