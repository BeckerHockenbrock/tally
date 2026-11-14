"""Build the bundled common-food library from the official USDA SR Legacy CSV ZIP.
Usage: python3 scripts/import_usda.py /path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
Download: https://fdc.nal.usda.gov/download-datasets/
Data: USDA FoodData Central, SR Legacy (2018), CC0/public domain.
All reported nutrient amounts are retained; absent nutrients are not filled with zero.
"""
import csv
import io
import json
import math
from pathlib import Path
import sys
import zipfile

archive = zipfile.ZipFile(sys.argv[1])
def rows(name):
    path = next(n for n in archive.namelist() if n.endswith('/' + name))
    return csv.DictReader(io.TextIOWrapper(archive.open(path), 'utf-8-sig'))

# Canonical keys match the same nutrient in barcode data. Do not merge RAE/DFE/IU.
keys = {
    '1009':'starch', '1051':'water', '1010':'sucrose', '1011':'glucose',
    '1012':'fructose', '1013':'lactose', '1014':'maltose', '1075':'galactose',
    '1104':'vitamin-a-iu', '1110':'vitamin-d-iu',
    '1079':'fiber', '2000':'sugars', '1235':'added-sugars', '1258':'saturated-fat',
    '1257':'trans-fat', '1292':'monounsaturated-fat', '1293':'polyunsaturated-fat',
    '1253':'cholesterol', '1093':'sodium', '1092':'potassium', '1087':'calcium',
    '1089':'iron', '1090':'magnesium', '1091':'phosphorus', '1095':'zinc',
    '1098':'copper', '1101':'manganese', '1103':'selenium', '1100':'iodine',
    '1102':'molybdenum', '1106':'vitamin-a-rae', '1162':'vitamin-c',
    '1114':'vitamin-d', '1109':'vitamin-e', '1185':'vitamin-k', '1165':'vitamin-b1',
    '1166':'vitamin-b2', '1167':'vitamin-pp', '1170':'pantothenic-acid',
    '1175':'vitamin-b6', '1176':'biotin', '1177':'folates', '1190':'folate-dfe',
    '1186':'folic-acid', '1178':'vitamin-b12', '1180':'choline'
}
# One everyday choice per food. Explicit source IDs keep nutrition reproducible.
# Preparation stays visible beneath the simple name instead of creating duplicate rows.
choices = [
    ('169757', 'White Rice', '🍚', 'Cooked'),
    ('169704', 'Brown Rice', '🍚', 'Cooked'),
    ('169737', 'Pasta', '🍝', 'Cooked'),
    ('171477', 'Chicken Breast', '🍗', 'Cooked, skinless'),
    ('171794', 'Ground Beef', '🥩', 'Cooked, 90% lean'),
    ('175168', 'Salmon', '🐟', 'Cooked'),
    ('173709', 'Tuna', '🐟', 'Canned in water, drained'),
    ('175180', 'Shrimp', '🦐', 'Cooked'),
    ('173424', 'Eggs', '🥚', 'Hard-boiled'),
    ('172475', 'Tofu', '🧊', 'Firm'),
    ('173904', 'Oats', '🥣', 'Dry'),
    ('172688', 'Bread', '🍞', 'Whole wheat'),
    ('168917', 'Quinoa', '🌾', 'Cooked'),
    ('171267', 'Milk', '🥛', '2% milk'),
    ('170894', 'Greek Yogurt', '🥣', 'Plain, nonfat'),
    ('173414', 'Cheese', '🧀', 'Cheddar'),
    ('172182', 'Cottage Cheese', '🥣', '2% milkfat'),
    ('173944', 'Banana', '🍌', 'Fresh'),
    ('171688', 'Apple', '🍎', 'Fresh, with skin'),
    ('169097', 'Orange', '🍊', 'Fresh'),
    ('167762', 'Strawberries', '🍓', 'Fresh'),
    ('171711', 'Blueberries', '🫐', 'Fresh'),
    ('174683', 'Grapes', '🍇', 'Fresh'),
    ('171705', 'Avocado', '🥑', 'Fresh'),
    ('169118', 'Pear', '🍐', 'Fresh'),
    ('169124', 'Pineapple', '🍍', 'Fresh'),
    ('167765', 'Watermelon', '🍉', 'Fresh'),
    ('169967', 'Broccoli', '🥦', 'Cooked'),
    ('170393', 'Carrot', '🥕', 'Raw'),
    ('168462', 'Spinach', '🥬', 'Raw'),
    ('169247', 'Lettuce', '🥬', 'Romaine, raw'),
    ('170457', 'Tomato', '🍅', 'Raw'),
    ('168409', 'Cucumber', '🥒', 'Raw, with peel'),
    ('170000', 'Onion', '🧅', 'Raw'),
    ('170108', 'Bell Pepper', '🫑', 'Raw'),
    ('169251', 'Mushrooms', '🍄', 'Raw'),
    ('170093', 'Potato', '🥔', 'Baked'),
    ('168483', 'Sweet Potato', '🍠', 'Baked'),
    ('173735', 'Black Beans', '🫘', 'Cooked'),
    ('173757', 'Chickpeas', '🫘', 'Cooked'),
    ('172421', 'Lentils', '🫘', 'Cooked'),
    ('170567', 'Almonds', '🥜', 'Plain'),
    ('170187', 'Walnuts', '🥜', 'Plain'),
    ('170162', 'Cashews', '🥜', 'Plain'),
    ('170554', 'Chia Seeds', '🌱', 'Dry'),
    ('174266', 'Peanut Butter', '🥜', 'Smooth'),
    ('171413', 'Olive Oil', '🫒', 'Plain'),
    ('173410', 'Butter', '🧈', 'Salted'),
    ('169640', 'Honey', '🍯', 'Plain'),
    ('169655', 'Sugar', '🍬', 'Granulated'),
    ('173468', 'Salt', '🧂', 'Table salt'),
    ('173647', 'Water', '💧', 'Drinking water'),
]
foods = {food['fdc_id']: food for food in rows('food.csv')}
selected = {fid: foods[fid] for fid, _, _, _ in choices}
presentation = {fid: (name, icon, preparation) for fid, name, icon, preparation in choices}
metadata = {n['id']: n for n in rows('nutrient.csv')}
amounts = {fid:{} for fid in selected}
for row in rows('food_nutrient.csv'):
    if row['fdc_id'] in selected and row['amount']:
        value = float(row['amount'])
        if math.isfinite(value) and value >= 0:
            amounts[row['fdc_id']][row['nutrient_id']] = value
portions = {}
for row in rows('food_portion.csv'):
    if row['fdc_id'] in selected and row['gram_weight'] and row['amount']:
        weight = float(row['gram_weight']) / float(row['amount'])
        if weight > 0 and row['fdc_id'] not in portions:
            portions[row['fdc_id']] = (weight, row['modifier'])
source = 'USDA SR Legacy (2018)'
output = []
for fid, food in selected.items():
    values = amounts[fid]
    if not all(k in values for k in ['1008','1003','1005','1004']):
        continue
    def nutrition(scale):
        nutrients = {}
        for nid, value in values.items():
            if nid in ['1008','1003','1005','1004','1062']:
                continue
            meta = metadata[nid]
            unit = {'G':'g','MG':'mg','UG':'µg','KCAL':'kcal'}.get(meta['unit_name'],meta['unit_name'])
            nutrients[keys.get(nid, 'usda-' + nid)] = dict(name=meta['name'],unit=unit,amount=value*scale,source=source)
        return dict(calories=values['1008']*scale, protein=values['1003']*scale,
                    carbs=values['1005']*scale, fat=values['1004']*scale,
                    energyEstimated=False, nutrients=nutrients)
    name, icon, preparation = presentation[fid]
    result = dict(barcode='usda:'+fid,name=name,icon=icon,preparation=preparation,
                  sourceDescription=food['description'],source=source,
                  portions=[dict(unit='grams',nutrition=nutrition(.01))])
    if fid in portions:
        weight, label = portions[fid]
        result['servingSize'] = f'1 {label} ({weight:g} g)'
        result['portions'].append(dict(unit='servings',nutrition=nutrition(weight/100)))
    output.append(result)
path = Path(__file__).resolve().parents[1] / 'Tally' / 'CommonFoods.json'
path.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':'))+'\n')
print(f'{len(output)} foods, {path.stat().st_size:,} bytes')
