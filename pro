#!/bin/bash
###Les variables 
#les variables modifiables par l'administrateur 
TAPE="/home/thor/Desktop/BACHUP.dump"
USERMAIL="khalil.belhaj.etu20@ensem.ac.ma"
Rep_sauve="/sauvegardes"
##############
#les variables du script 
FicLog="${Rep_sauve}/sauvesys.log"
Date="`date +%d-%m-%y`"
SERVER="`uname -n`"
PATH=$PATH:/user/sbin:/sbin
fstab="/etc/fstab"
ListeFS=""
ListeRaid1=""
ListeLVM=""
ListeOrdre=""
MesPB=""
###La phase préparatoire
#partie 1
#creation du répertoire de sauvegard 
[ -d $Rep_sauve ] || mkdir -p $Rep_sauve
#partie 2
#initialisation du fichier de journalisation 
cat /dev/null > ${FicLog}    ### probleme de permission

#partie 3
#affichage de message vers la sortie standard
#si le script est execute sue la ligne de commande
#ce message n apparait pas lors d un exécution par contrab(ou tout 
#ordonnanceur ou séquenceur )     
if [ "`tty | cut -c 1-8`" = "/dev/tty" ]
then 
	echo -e "\n Debut de la sauvegarde systéme par #dump du serveur $SERVER \
	\n Merci de partienter, la procedure est longue.\
      \n Vous pouvez consulter le fichier de log pour suivre \nl'avancement de la sauvgarde\n"
	echo -e "Lancement de la SAUVEGARD SYSTEME \
		      \nServeur; $SERVER \
	\n$(date +'DATE: %d/%m/%y%tHEURE: %H:%M:%S') \n" >> ${FicLog}
fi

####La Phase 2
#partie1
#quelque fichiers systémes 
cp -p /etc/fstab ${Rep_sauve}/fstab.$Date
cp /boot/grub/grub.cfg ${Rep_sauve}/grub.cfg.$Date
#partie 2
Liste="`ls /dev/sd[a-z] 2>/dev/null` `ls /dev/hd[a-z] 2>/dev/null` "
for disk in $Liste 
do
	fdisk -l $disk > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
		fdisk -l ${disk} > ${Rep_sauve}/vtoc.$Date.`echo ${disk} | cut -c 6-8`
	dd if=${disk} of=${Rep_sauve}/mbr.$Date.`echo ${disk} | cut -c 6-8` bs=512 count=1 > /dev/null 2>&1
	fi
done

#partie 3
######phase3 FS
#partie1
tab=('')
let "i=0"
let "c=0"
twc="`cat /etc/fstab | grep -v '^#' | grep 'ext'`"
for p in $twc
do
	let "b=i%6"
	if [ $b -eq 0 ]
	then
		t="`echo $p | cut -c 1-5`"
		if [ $t = "UUID=" ] || [ $t = "LABEL" ]
		then
			z="`findfs $p`"
			tab[$c]=$z
			let "c+=1"
		else
		       	tab[$c]=$p
			let "c+=1"
		fi
	fi
	let "i+=1"
done
ListeFS="${tab[*]}"

###ListeLVM le supprime de ListeFS
newLVM=("")
newFS=("")
let "q=0"
let "p=0"
for fs in $ListeFS
do
	if [ `echo $fs |cut -c 1-11` == "/dev/mapper" ]
	then
		newLVM[$q]=$fs
		let "q+=1"
	else
		newFS[$p]=$fs
		let "p+=1"
	fi
done
ListeFS="${newFS[*]}"
ListeLVM="${newLVM[*]}"

#partie2
#recup les raid1 dans ListRaid1  
for element in $ListeFS
do
	if (mdadm --detail $element |grep "raid1" ) > /dev/null 2>&1
	then
		nbsm=$(mdadm --detail $element|grep "active"|awk '{print $NF}'|wc -l) 
		if [ $nbsm -gt 1 ]
		then
			ListeRaid1=${ListeRaid1}" $element "$(mdadm --detail $element|grep "active"|awk '{print $NF}'|tail -l)
		else
			echo -e "PROBLEME pour $element \nLe nombre \
				de sous-miroirs est insuffisant." >> ${FicLog}
			MesPB=$MesPB"\nSauvegarde de $element non realisee: \
                probleme sur sa configuration."
		fi
	fi
done


#le supprime de ListeFS les raid1
tmp=""
tabt=("")
let "k=0"
let "i=0"
for liste in $ListeFS
do
	let "k=0"
	for raid in $ListeRaid1
	do
		if [ $raid == $liste ];then
			let "k=1"
		fi
	done
	if [ $k -eq 0 ];then
		tabt[$i]=$liste
		let "i+=1"
	fi
done
ListeFS="${tabt[*]}"


#####PAHSE 3
#PARTIE1
#SAUVEGARD DE LISTEFS UTILISANT DUMP

set -- $ListeFS
if [ "$#" -ne 0 ]
then
	for liste in $ListeFS
	do
		echo -e "\nENTRAIN DE SAUVEGARDER LE FICHIER DE SYSTEM: $liste "
		dump -0uf ${TAPE} $liste >> /dev/null 2>&1
		if [ "$?" -ne 0 ]
		then
			MesPB=${MesPB}"\nEchec Sauvegard de $liste"
		else
			echo -e "\nSauvegard de $fs realisé avec succes." 
			ListeOrdre=${ListeOrdre}"$ (mount |grep $liste| awk '{print $3}'"
		fi
	done >> ${FicLog} 2>&1
fi


table=("")
let "o=0"
for liste in $ListeLVM
do
	table[$o]="/dev/mapper/vg-ENSEM/lv-`echo $liste | cut -c 27-`"
	let "o+=1"
done
ListeLVM="${table[*]}"

if [ -n "$ListeLVM"]
then
for liste in $ListeLVM
do
	lvcreate --size 500M -s -n lensnap $liste
     	echo -e "\nENTRAIN DE SAUVEGARDER LE FICHIER DE SYSTEM: $liste "
     	dump -0uf ${TAPE} /dev/vg-ENSEM/lesnap >> /dev/null 2>&1 
     	if [ "$?" -ne 0 ]
     	then
      		MesPB=${MesPB}"\nEchec Sauvegard de $liste"
     	else 
      		echo -e "\nSauvegard de $fs realisé avec succes." 

      		ListeOrdre=${ListeOrdre}"$ (mount |grep vg--ENSEM-lv--`echo $liste | cut -c 27-`| awk '{print $3}'"   
    	fi
    	lvremove -f /dev/vg-ENSEM/lensnap
done >> ${FicLog} 2>&1
fi


###PARTIE 2:SAUVEGARD DE LISTELVM
#if [ -n "$ListeLVM" ]
#then
#	for liste in $ListeLVM
#	do
#		vg=`echo $liste|awk -F"/" '{print $4}'|awk -F"--" '{print $1}'`
#		lv=`echo $liste|awk -F"/" '{print $4}'|awk -F"--" '{print $2}'`
#		lvcreate --size 500M -s -n lesnap $liste
#		echo -e "\nENTRAIN DE SAUVEGARDER LE FICHIER DE SYSTEM: $liste "
#    		dump -0uf ${TAPE} /dev/${vg}/lesnap >> /dev/null 2>&1 
#     		if [ "$?" -ne 0 ]
#		then
#			MesPB=${MesPB}"\nEchec Sauvegard de $liste"
#		else
#			echo -e "\nSauvegard de $fs realisé avec succes." 
#
#      			ListeOrdre=${ListeOrdre}"$ (mount |grep $vg-$lv| awk '{print $3}'"
#		fi
#		lvremove -f /dev/${vg}/lensnap
#	done >> ${F:icLog} 2>&1
#fi






###Partie3:SAUVEGARD DE FS RAID PAR DUMP
if [  -n "$ListeRaid1" ]
then
	set -- $ListeRaid1
 	while [ $# -ne 0 ]
 	do
		echo -e "\nProcedure RAID1"
 		mdadm $1 --fail $2
		mdadm $1 --remove $2
		echo -e "\n+ Sauvegarde RAID1 de $1"
		dump 0uf ${TAPE} $2
  		if [ $? -ne 0 ]
		then
			MesPB=$ {MesPB}"\nEchec Sauvegarde de $1"
		else
			echo -e "\nSauvegarde de $1 realisee avec succes."
			ListeOrdre=${ListeOrdre}" $(mount |grep "$1"|awk '{print $3}')"
		fi
		mdadm $1 --add $2
		shift 2
	done >> ${FicLog} 2>&1
fi



####Phase final 
#partie 1
# La liste final des problémes 
echo -e "\n\nListe des problémes:\n" > ${FicLog}
if [ -z "MesPB" ]
then
	echo -e "Aucun Probléme:" >> ${FicLog}
else
	echo -e "MesPB" >> ${FicLog}           
fi      
#Partie 2
#Mail de rapport 
cat ${FicLog}|ssmtp $USERMAIL 
#partie 3
# syslog
if [ -z "$MesPB" ];then
	logger -i -p local1.info "Sauvegarde de systéme est bien realisé!"
else 
	logger -i -p local1.info "Sauveguard systéme en Echec voir $FicLog pour plus de détail."
	logger -i -p local2.err "Sauveguard systéme en Echec voir $FicLog pour plus de détail."
fi



